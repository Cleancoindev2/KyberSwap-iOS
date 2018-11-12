// Copyright SIX DAY LLC. All rights reserved.

import UIKit
import BigInt

protocol KNBalanceTabCoordinatorDelegate: class {
  func balanceTabCoordinatorShouldOpenExchange(for tokenObject: TokenObject, isReceived: Bool)
  func balanceTabCoordinatorDidSelect(walletObject: KNWalletObject)
  func balancetabCoordinatorDidSelectAddWallet()
}

class KNBalanceTabCoordinator: Coordinator {

  let navigationController: UINavigationController
  private(set) var session: KNSession
  var coordinators: [Coordinator] = []

  fileprivate var balances: [String: Balance] = [:]

  weak var delegate: KNBalanceTabCoordinatorDelegate?

  lazy var newRootViewController: KWalletBalanceViewController = {
    let address: String = self.session.wallet.address.description
    let wallet: KNWalletObject = KNWalletStorage.shared.get(forPrimaryKey: address) ?? KNWalletObject(address: address)
    let viewModel: KWalletBalanceViewModel = KWalletBalanceViewModel(wallet: wallet)
    let controller: KWalletBalanceViewController = KWalletBalanceViewController(viewModel: viewModel)
    controller.delegate = self
    controller.loadViewIfNeeded()
    return controller
  }()

  fileprivate var qrcodeCoordinator: KNWalletQRCodeCoordinator? {
    guard let walletObject = KNWalletStorage.shared.get(forPrimaryKey: self.session.wallet.address.description) else { return nil }
    let qrcodeCoordinator = KNWalletQRCodeCoordinator(
      navigationController: self.navigationController,
      walletObject: walletObject
    )
    return qrcodeCoordinator
  }

  lazy var historyCoordinator: KNHistoryCoordinator = {
    let coordinator = KNHistoryCoordinator(
      navigationController: self.navigationController,
      session: self.session)
    return coordinator
  }()

  fileprivate var sendTokenCoordinator: KNSendTokenViewCoordinator?
  fileprivate var tokenChartCoordinator: KNTokenChartCoordinator?

  init(
    navigationController: UINavigationController = UINavigationController(),
    session: KNSession
    ) {
    self.navigationController = navigationController
    self.navigationController.setNavigationBarHidden(true, animated: false)
    self.session = session
  }

  func start() {
    let tokenObjects: [TokenObject] = self.session.tokenStorage.tokens
    self.newRootViewController.coordinatorUpdateTokenObjects(tokenObjects)
    self.navigationController.viewControllers = [self.newRootViewController]
  }

  func stop() { }
}

// Update from appcoordinator
extension KNBalanceTabCoordinator {
  func appCoordinatorDidUpdateNewSession(_ session: KNSession, resetRoot: Bool = false) {
    self.session = session
    if resetRoot {
      self.navigationController.popToRootViewController(animated: true)
    }

    let viewModel: KWalletBalanceViewModel = {
      let tokenObjects: [TokenObject] = self.session.tokenStorage.tokens
      let address: String = session.wallet.address.description
      let walletObject = KNWalletStorage.shared.get(forPrimaryKey: address) ?? KNWalletObject(address: address)
      let viewModel = KWalletBalanceViewModel(wallet: walletObject)
      _ = viewModel.updateTokenObjects(tokenObjects)
      return viewModel
    }()
    self.newRootViewController.coordinatorUpdateSessionWithNewViewModel(viewModel)
    let pendingObjects = self.session.transactionStorage.kyberPendingTransactions
    self.newRootViewController.coordinatorUpdatePendingTransactions(pendingObjects)
    self.historyCoordinator.appCoordinatorPendingTransactionDidUpdate(pendingObjects)
  }

  func appCoordinatorDidUpdateWalletObjects() {
    self.newRootViewController.coordinatorUpdateWalletObjects()
    self.historyCoordinator.appCoordinatorDidUpdateWalletObjects()
  }

  func appCoordinatorTokenBalancesDidUpdate(
    totalBalanceInUSD: BigInt,
    totalBalanceInETH: BigInt,
    otherTokensBalance: [String: Balance]
    ) {
    self.newRootViewController.coordinatorUpdateTokenBalances(otherTokensBalance)
    self.appCoordinatorExchangeRateDidUpdate(
      totalBalanceInUSD: totalBalanceInUSD,
      totalBalanceInETH: totalBalanceInETH
    )
    otherTokensBalance.forEach { self.balances[$0.key] = $0.value }
    self.tokenChartCoordinator?.coordinatorTokenBalancesDidUpdate(balances: self.balances)
    self.sendTokenCoordinator?.coordinatorTokenBalancesDidUpdate(balances: self.balances)
  }

  func appCoordinatorETHBalanceDidUpdate(
    totalBalanceInUSD: BigInt,
    totalBalanceInETH: BigInt,
    ethBalance: Balance
    ) {
    if let ethToken = KNSupportedTokenStorage.shared.supportedTokens.first(where: { $0.isETH }) {
      self.newRootViewController.coordinatorUpdateTokenBalances([ethToken.contract: ethBalance])
      self.balances[ethToken.contract] = ethBalance
    }
    self.appCoordinatorExchangeRateDidUpdate(
      totalBalanceInUSD: totalBalanceInUSD,
      totalBalanceInETH: totalBalanceInETH
    )
    self.tokenChartCoordinator?.coordinatorTokenBalancesDidUpdate(balances: self.balances)
    self.sendTokenCoordinator?.coordinatorETHBalanceDidUpdate(ethBalance: ethBalance)
  }

  func appCoordinatorExchangeRateDidUpdate(
    totalBalanceInUSD: BigInt,
    totalBalanceInETH: BigInt
    ) {
    self.tokenChartCoordinator?.coordinatorExchangeRateDidUpdate()
    self.newRootViewController.coordinatorUpdateBalanceInETHAndUSD(
      ethBalance: totalBalanceInETH,
      usdBalance: totalBalanceInUSD
    )
  }

  func appCoordinatorTokenObjectListDidUpdate(_ tokenObjects: [TokenObject]) {
    self.newRootViewController.coordinatorUpdateTokenObjects(tokenObjects)
    self.tokenChartCoordinator?.coordinatorTokenObjectListDidUpdate(tokenObjects)
    self.sendTokenCoordinator?.coordinatorTokenObjectListDidUpdate(tokenObjects)
  }

  func appCoordinatorSupportedTokensDidUpdate(tokenObjects: [TokenObject]) {
    let tokens = self.session.tokenStorage.tokens
    self.newRootViewController.coordinatorUpdateTokenObjects(tokens)
    self.tokenChartCoordinator?.coordinatorTokenObjectListDidUpdate(tokens)
  }

  func appCoordinatorPendingTransactionsDidUpdate(transactions: [KNTransaction]) {
    self.newRootViewController.coordinatorUpdatePendingTransactions(transactions)
    self.historyCoordinator.appCoordinatorPendingTransactionDidUpdate(transactions)
  }

  func appCoordinatorGasPriceCachedDidUpdate() {
    self.sendTokenCoordinator?.coordinatorGasPriceCachedDidUpdate()
    self.tokenChartCoordinator?.coordinatorGasPriceCachedDidUpdate()
  }

  func appCoordinatorTokensTransactionsDidUpdate() {
    self.historyCoordinator.appCoordinatorTokensTransactionsDidUpdate()
  }
}

// MARK: New Design K Wallet Balance delegation
extension KNBalanceTabCoordinator: KWalletBalanceViewControllerDelegate {
  func kWalletBalanceViewController(_ controller: KWalletBalanceViewController, run event: KWalletBalanceViewEvent) {
    switch event {
    case .openQRCode:
      self.qrcodeCoordinator?.start()
    case .selectToken(let token):
      self.openTokenChartView(for: token)
    case .send(let token):
      self.openSendTokenView(with: token)
    case .sell(let token):
      self.delegate?.balanceTabCoordinatorShouldOpenExchange(for: token, isReceived: false)
    case .buy(let token):
      self.delegate?.balanceTabCoordinatorShouldOpenExchange(for: token, isReceived: true)
    case .receiveToken:
      self.qrcodeCoordinator?.start()
    }
  }

  func kWalletBalanceViewController(_ controller: KWalletBalanceViewController, run menuEvent: KNBalanceTabHamburgerMenuViewEvent) {
    switch menuEvent {
    case .select(let wallet):
      self.hamburgerMenu(select: wallet)
    case .selectAddWallet:
      self.hamburgerMenuSelectAddWallet()
    case .selectSendToken:
      self.openSendTokenView(with: self.session.tokenStorage.ethToken)
    case .selectAllTransactions:
      self.openHistoryTransactionView()
    }
  }

  fileprivate func openTokenChartView(for tokenObject: TokenObject) {
    self.tokenChartCoordinator = KNTokenChartCoordinator(
      navigationController: self.navigationController,
      session: self.session,
      balances: self.balances,
      token: tokenObject
    )
    self.tokenChartCoordinator?.delegate = self
    self.tokenChartCoordinator?.start()
  }

  func hamburgerMenu(select walletObject: KNWalletObject) {
    self.delegate?.balanceTabCoordinatorDidSelect(walletObject: walletObject)
  }

  func hamburgerMenuSelectAddWallet() {
    self.delegate?.balancetabCoordinatorDidSelectAddWallet()
  }

  func openSendTokenView(with token: TokenObject) {
    self.sendTokenCoordinator = KNSendTokenViewCoordinator(
      navigationController: self.navigationController,
      session: self.session,
      balances: self.balances,
      from: token
    )
    self.sendTokenCoordinator?.start()
  }

  func openHistoryTransactionView() {
    self.historyCoordinator.appCoordinatorDidUpdateNewSession(self.session)
    self.historyCoordinator.start()
  }
}

// MARK: New Token Delegate
extension KNBalanceTabCoordinator: NewTokenViewControllerDelegate {
  func didAddToken(token: ERC20Token, in viewController: NewTokenViewController) {
    self.session.tokenStorage.addCustom(token: token)
    self.navigationController.topViewController?.dismiss(animated: true, completion: {
      KNNotificationUtil.postNotification(for: kTokenObjectListDidUpdateNotificationKey)
    })
  }

  func didCancel(in viewController: NewTokenViewController) {
    self.navigationController.topViewController?.dismiss(animated: true, completion: nil)
  }
}

// MARK: Token Chart Coordinator Delegate
extension KNBalanceTabCoordinator: KNTokenChartCoordinatorDelegate {
  func tokenChartCoordinator(sell token: TokenObject) {
    self.delegate?.balanceTabCoordinatorShouldOpenExchange(for: token, isReceived: false)
  }

  func tokenChartCoordinator(buy token: TokenObject) {
    self.delegate?.balanceTabCoordinatorShouldOpenExchange(for: token, isReceived: true)
  }
}