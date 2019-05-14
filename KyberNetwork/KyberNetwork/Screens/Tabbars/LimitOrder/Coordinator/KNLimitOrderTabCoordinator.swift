// Copyright SIX DAY LLC. All rights reserved.

import UIKit
import BigInt
import TrustKeystore
import TrustCore
import Result
import Moya
import APIKit

protocol KNLimitOrderTabCoordinatorDelegate: class {
  func limitOrderTabCoordinatorDidSelectWallet(_ wallet: KNWalletObject)
  func limitOrderTabCoordinatorRemoveWallet(_ wallet: Wallet)
  func limitOrderTabCoordinatorDidSelectAddWallet()
  func limitOrderTabCoordinatorDidSelectPromoCode()
}

class KNLimitOrderTabCoordinator: Coordinator {

  let navigationController: UINavigationController
  var session: KNSession
  var tokens: [TokenObject] = KNSupportedTokenStorage.shared.supportedTokens
  var isSelectingSourceToken: Bool = true
  var coordinators: [Coordinator] = []

  weak var delegate: KNLimitOrderTabCoordinatorDelegate?

  fileprivate var balances: [String: Balance] = [:]

  fileprivate var historyCoordinator: KNHistoryCoordinator?
  fileprivate var searchTokensViewController: KNSearchTokenViewController?
  fileprivate var sendTokenCoordinator: KNSendTokenViewCoordinator?

  lazy var rootViewController: KNCreateLimitOrderViewController = {
    let (from, to): (TokenObject, TokenObject) = {
      let address = self.session.wallet.address.description
      let destToken = KNWalletPromoInfoStorage.shared.getDestinationToken(from: address)
      if let dest = destToken, let from = KNSupportedTokenStorage.shared.ptToken {
        let to = KNSupportedTokenStorage.shared.supportedTokens.first(where: { $0.symbol == dest.uppercased() }) ?? KNSupportedTokenStorage.shared.ethToken
        return (from, to)
      }
      return (KNSupportedTokenStorage.shared.kncToken, KNSupportedTokenStorage.shared.ethToken)
    }()
    let viewModel = KNCreateLimitOrderViewModel(
      wallet: self.session.wallet,
      from: from,
      to: to,
      supportedTokens: tokens
    )
    let controller = KNCreateLimitOrderViewController(viewModel: viewModel)
    controller.loadViewIfNeeded()
    controller.delegate = self
    return controller
  }()

  init(
    navigationController: UINavigationController = UINavigationController(),
    session: KNSession
  ) {
    self.navigationController = navigationController
    self.navigationController.setNavigationBarHidden(true, animated: false)
    self.session = session
  }

  func start() {
    self.navigationController.viewControllers = [self.rootViewController]
  }
}

// MARK: Update from app coordinator
extension KNLimitOrderTabCoordinator {
  func appCoordinatorDidUpdateNewSession(_ session: KNSession, resetRoot: Bool = false) {
    self.session = session
    self.rootViewController.coordinatorUpdateNewSession(wallet: session.wallet)
    if resetRoot {
      self.navigationController.popToRootViewController(animated: false)
    }
    let pendingTrans = self.session.transactionStorage.kyberPendingTransactions
    self.rootViewController.coordinatorDidUpdatePendingTransactions(pendingTrans)
    if self.navigationController.viewControllers.first(where: { $0 is KNHistoryViewController }) == nil {
      self.historyCoordinator = nil
      self.historyCoordinator = KNHistoryCoordinator(
        navigationController: self.navigationController,
        session: self.session
      )
    }
    self.historyCoordinator?.delegate = self
    self.historyCoordinator?.appCoordinatorPendingTransactionDidUpdate(pendingTrans)
  }

  func appCoordinatorDidUpdateWalletObjects() {
    self.rootViewController.coordinatorUpdateWalletObjects()
    self.historyCoordinator?.appCoordinatorDidUpdateWalletObjects()
  }

  func appCoordinatorGasPriceCachedDidUpdate() {
    self.sendTokenCoordinator?.coordinatorGasPriceCachedDidUpdate()
  }

  func appCoordinatorTokenBalancesDidUpdate(totalBalanceInUSD: BigInt, totalBalanceInETH: BigInt, otherTokensBalance: [String: Balance]) {
    self.rootViewController.coordinatorUpdateTokenBalance(otherTokensBalance)
    otherTokensBalance.forEach { self.balances[$0.key] = $0.value }
    self.sendTokenCoordinator?.coordinatorTokenBalancesDidUpdate(balances: self.balances)
    self.searchTokensViewController?.updateBalances(otherTokensBalance)
  }

  func appCoordinatorETHBalanceDidUpdate(totalBalanceInUSD: BigInt, totalBalanceInETH: BigInt, ethBalance: Balance) {
    if let eth = self.tokens.first(where: { $0.isETH }) {
      self.balances[eth.contract] = ethBalance
      self.searchTokensViewController?.updateBalances([eth.contract: ethBalance])
      self.rootViewController.coordinatorUpdateTokenBalance([eth.contract: ethBalance])
    }
    self.sendTokenCoordinator?.coordinatorETHBalanceDidUpdate(ethBalance: ethBalance)
  }

  func appCoordinatorUSDRateDidUpdate(totalBalanceInUSD: BigInt, totalBalanceInETH: BigInt) {
    self.rootViewController.coordinatorTrackerRateDidUpdate()
    self.sendTokenCoordinator?.coordinatorDidUpdateTrackerRate()
  }

  func appCoordinatorUpdateExchangeTokenRates() {
    self.rootViewController.coordinatorUpdateProdCachedRates()
  }

  func appCoordinatorTokenObjectListDidUpdate(_ tokenObjects: [TokenObject]) {
    let supportedTokens = KNSupportedTokenStorage.shared.supportedTokens
    self.tokens = supportedTokens
    self.sendTokenCoordinator?.coordinatorTokenObjectListDidUpdate(tokenObjects)
    self.searchTokensViewController?.updateListSupportedTokens(supportedTokens)
  }

  func appCoordinatorPendingTransactionsDidUpdate(transactions: [KNTransaction]) {
    self.rootViewController.coordinatorDidUpdatePendingTransactions(transactions)
    self.historyCoordinator?.appCoordinatorPendingTransactionDidUpdate(transactions)
  }

  func appCoordinatorTokensTransactionsDidUpdate() {
    self.historyCoordinator?.appCoordinatorTokensTransactionsDidUpdate()
  }
}

extension KNLimitOrderTabCoordinator: KNCreateLimitOrderViewControllerDelegate {
  func kCreateLimitOrderViewController(_ controller: KNCreateLimitOrderViewController, run event: KNCreateLimitOrderViewEvent) {
    switch event {
    case .searchToken(let from, let to, let isSource):
      self.openSearchToken(from: from, to: to, isSource: isSource)
    case .estimateRate(let from, let to, let amount, let showWarning):
      self.updateEstimatedRate(from: from, to: to, amount: amount, showError: showWarning, completion: nil)
    case .submitOrder(let order):
      self.signAndSendOrder(order)
    default: break
    }
  }

  func kCreateLimitOrderViewController(_ controller: KNCreateLimitOrderViewController, run event: KNBalanceTabHamburgerMenuViewEvent) {
    switch event {
    case .selectSendToken:
      self.openSendTokenView()
    case .selectAddWallet:
      self.openAddWalletView()
    case .select(let wallet):
      self.updateCurrentWallet(wallet)
    case .selectPromoCode:
      self.openPromoCodeView()
    case .selectAllTransactions:
      self.openHistoryTransactionsView()
    }
  }

  fileprivate func signAndSendOrder(_ order: KNLimitOrder) {
    let result = self.session.keystore.signLimitOrder(order)
    switch result {
    case .success:
      self.navigationController.showSuccessTopBannerMessage(
        with: NSLocalizedString("success", comment: ""),
        message: "Successfully signed the order data".toBeLocalised(),
        time: 1.5
      )
    case .failure(let error):
      self.navigationController.showErrorTopBannerMessage(
        with: NSLocalizedString("error", comment: ""),
        message: "Can not sign your order, error: \(error.prettyError)".toBeLocalised(),
        time: 1.5
      )
    }
  }

  fileprivate func openPromoCodeView() {
    self.delegate?.limitOrderTabCoordinatorDidSelectPromoCode()
  }

  fileprivate func openAddWalletView() {
    self.delegate?.limitOrderTabCoordinatorDidSelectAddWallet()
  }

  fileprivate func updateCurrentWallet(_ wallet: KNWalletObject) {
    self.delegate?.limitOrderTabCoordinatorDidSelectWallet(wallet)
  }

  fileprivate func openHistoryTransactionsView() {
    self.historyCoordinator = nil
    self.historyCoordinator = KNHistoryCoordinator(
      navigationController: self.navigationController,
      session: self.session
    )
    self.historyCoordinator?.delegate = self
    self.historyCoordinator?.appCoordinatorDidUpdateNewSession(self.session)
    self.historyCoordinator?.start()
  }

  fileprivate func openSearchToken(from: TokenObject, to: TokenObject, isSource: Bool) {
    self.isSelectingSourceToken = isSource
    self.tokens = KNSupportedTokenStorage.shared.supportedTokens
    self.searchTokensViewController = {
      let viewModel = KNSearchTokenViewModel(
        headerColor: KNAppStyleType.current.swapHeaderBackgroundColor,
        supportedTokens: self.tokens
      )
      let controller = KNSearchTokenViewController(viewModel: viewModel)
      controller.loadViewIfNeeded()
      controller.delegate = self
      return controller
    }()
    self.navigationController.pushViewController(self.searchTokensViewController!, animated: true)
    self.searchTokensViewController?.updateBalances(self.balances)
  }

  fileprivate func openSendTokenView() {
    if self.session.transactionStorage.kyberPendingTransactions.isEmpty {
      self.sendTokenCoordinator = KNSendTokenViewCoordinator(
        navigationController: self.navigationController,
        session: self.session,
        balances: self.balances,
        from: self.session.tokenStorage.ethToken
      )
      self.sendTokenCoordinator?.start()
    } else {
      let message = NSLocalizedString("Please wait for other transactions to be mined before making a transfer", comment: "")
      self.navigationController.showWarningTopBannerMessage(
        with: "",
        message: message,
        time: 2.0
      )
    }
  }

  // Call contract to get estimate rate with src, dest, srcAmount
  fileprivate func updateEstimatedRate(from: TokenObject, to: TokenObject, amount: BigInt, showError: Bool, completion: ((Error?) -> Void)? = nil) {
    self.getExpectedExchangeRate(from: from, to: to, amount: amount) { [weak self] result in
      guard let `self` = self else { return }
      switch result {
      case .success(let data):
        self.rootViewController.coordinatorDidUpdateEstimateRate(
          from: from,
          to: to,
          amount: amount,
          rate: data.0,
          slippageRate: data.1
        )
        completion?(nil)
      case .failure(let error):
        if showError {
          if case let err as APIKit.SessionTaskError = error.error, case .connectionError = err {
            self.navigationController.showErrorTopBannerMessage(
              with: NSLocalizedString("error", value: "Error", comment: ""),
              message: NSLocalizedString("please.check.your.internet.connection", value: "Please check your internet connection", comment: ""),
              time: 1.5
            )
          } else {
            self.navigationController.showErrorTopBannerMessage(
              with: NSLocalizedString("error", value: "Error", comment: ""),
              message: NSLocalizedString("can.not.update.exchange.rate", comment: "Can not update exchange rate"),
              time: 1.5
            )
          }
          self.rootViewController.coordinatorDidUpdateEstimateRate(
            from: from,
            to: to,
            amount: amount,
            rate: BigInt(0),
            slippageRate: BigInt(0)
          )
        }
        completion?(error)
      }
    }
  }

  fileprivate func getExpectedExchangeRate(from: TokenObject, to: TokenObject, amount: BigInt, completion: ((Result<(BigInt, BigInt), AnyError>) -> Void)? = nil) {
    if from == to {
      let rate = BigInt(10).power(from.decimals)
      let slippageRate = rate * BigInt(97) / BigInt(100)
      completion?(.success((rate, slippageRate)))
      return
    }
    self.session.externalProvider.getExpectedRate(
      from: from,
      to: to,
      amount: amount) { (result) in
        var estRate: BigInt = BigInt(0)
        var slippageRate: BigInt = BigInt(0)
        switch result {
        case .success(let data):
          estRate = data.0
          slippageRate = data.1
          estRate /= BigInt(10).power(18 - to.decimals)
          slippageRate /= BigInt(10).power(18 - to.decimals)
          completion?(.success((estRate, slippageRate)))
        case .failure(let error):
          completion?(.failure(error))
        }
    }
  }
}

extension KNLimitOrderTabCoordinator: KNHistoryCoordinatorDelegate {
  func historyCoordinatorDidClose() {
    //    self.historyCoordinator = nil
  }
}

// MARK: Search token
extension KNLimitOrderTabCoordinator: KNSearchTokenViewControllerDelegate {
  func searchTokenViewController(_ controller: KNSearchTokenViewController, run event: KNSearchTokenViewEvent) {
    self.navigationController.popViewController(animated: true) {
      self.searchTokensViewController = nil
      if case .select(let token) = event {
        self.rootViewController.coordinatorUpdateSelectedToken(
          token,
          isSource: self.isSelectingSourceToken
        )
      }
    }
  }
}
