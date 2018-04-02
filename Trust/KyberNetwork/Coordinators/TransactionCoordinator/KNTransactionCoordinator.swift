// Copyright SIX DAY LLC. All rights reserved.

import UIKit
import RealmSwift
import APIKit
import JSONRPCKit
import JavaScriptKit
import Result
import BigInt
import TrustKeystore
import Moya

class KNTransactionCoordinator {

  let storage: TransactionsStorage
  let externalProvider: KNExternalProvider
  fileprivate var pendingTxTimer: Timer?
  fileprivate var allTxTimer: Timer?

  init(storage: TransactionsStorage, externalProvider: KNExternalProvider) {
    self.storage = storage
    self.externalProvider = externalProvider
  }
}

// MARK: Lock data when user confirmed
extension KNTransactionCoordinator {

  // Prepare data before submitting exchange request
  // Data needed: gas limit, expected rate
  static func requestDataPrepareForExchangeTransaction(_ transaction: KNDraftExchangeTransaction, provider: KNExternalProvider, completion: @escaping (Result<KNDraftExchangeTransaction?, AnyError>) -> Void) {
    DispatchQueue.global().async {
      var error: AnyError?
      let group = DispatchGroup()

      // Est Gas Used
      var gasLimit = transaction.gasLimit ?? KNGasConfiguration.exchangeTokensGasLimitDefault
      group.enter()
      provider.getEstimateGasLimit(for: transaction) { result in
        switch result {
        case .success(let gas): gasLimit = gas
        // TODO (Mike): Est. Gas Limit is temp not working
        //case .failure(let err): error = err
        default: break
        }
        group.leave()
      }

      // Expected Rate
      var expectedRate = transaction.expectedRate
      group.enter()
      provider.getExpectedRate(
        from: transaction.from,
        to: transaction.to,
        amount: transaction.amount) { result in
          switch result {
          case .success(let data): expectedRate = data.0
          case .failure(let err): error = err
          }
          group.leave()
      }

      // Balance
      var balance = BigInt(0)
      group.enter()
      if transaction.from.isETH {
        provider.getETHBalance(completion: { result in
          switch result {
          case .success(let bal): balance = bal.value
          case .failure(let err): error = err
          }
          group.leave()
        })
      } else {
        provider.getTokenBalance(for: Address(string: transaction.from.address)!, completion: { result in
          switch result {
          case .success(let bal): balance = bal
          case .failure(let err): error = err
          }
          group.leave()
        })
      }

      group.notify(queue: .main) {
        if let err = error {
          completion(.failure(err))
          return
        }
        if balance < transaction.amount {
          completion(.success(nil))
          return
        }
        completion(.success(transaction.copy(expectedRate: expectedRate, gasLimit: gasLimit)))
      }
    }
  }

  // Prepare data before submitting transfer request
  // Data needed: gas limit
  static func requestDataPrepareForTransferTransaction(_ transaction: UnconfirmedTransaction, provider: KNExternalProvider, completion: @escaping (Result<UnconfirmedTransaction?, AnyError>) -> Void) {
    DispatchQueue.global().async {
      var error: AnyError?
      let group = DispatchGroup()

      let token: KNToken = transaction.transferType.knToken()

      // Est Gas Used
      var gasLimit: BigInt = {
        if let gas = transaction.gasLimit { return gas }
        return token.isETH ? KNGasConfiguration.transferETHGasLimitDefault : KNGasConfiguration.transferTokenGasLimitDefault
      }()
      group.enter()
      provider.getEstimateGasLimit(for: transaction) { result in
        switch result {
        case .success(let gas): gasLimit = gas
          // TODO (Mike): Est. Gas Limit is temp not working
        //case .failure(let err): error = err
        default: break
        }
        group.leave()
      }

      // Balance
      var balance = BigInt(0)
      group.enter()
      if token.isETH {
        provider.getETHBalance(completion: { result in
          switch result {
          case .success(let bal): balance = bal.value
          case .failure(let err): error = err
          }
          group.leave()
        })
      } else {
        provider.getTokenBalance(for: Address(string: token.address)!, completion: { result in
          switch result {
          case .success(let bal): balance = bal
          case .failure(let err): error = err
          }
          group.leave()
        })
      }

      group.notify(queue: .main) {
        if let err = error {
          completion(.failure(err))
          return
        }
        if balance < transaction.value {
          completion(.success(nil))
          return
        }
        let newTransaction = UnconfirmedTransaction(
          transferType: transaction.transferType,
          value: transaction.value,
          to: transaction.to,
          data: transaction.data,
          gasLimit: gasLimit,
          gasPrice: transaction.gasPrice,
          nonce: transaction.nonce
        )
        completion(.success(newTransaction))
      }
    }
  }
}

// MARK: Update transactions
extension KNTransactionCoordinator {
  func startUpdatingAllTransactions(for address: Address) {
    self.stopUpdatingAllTransactions()
    self.allTxTimer = Timer.scheduledTimer(
      withTimeInterval: KNLoadingInterval.defaultLoadingInterval,
      repeats: true,
      block: { [weak self] _ in
        guard let `self` = self else { return }
        let startBlock: Int = {
          guard let transaction = self.storage.completedObjects.first else { return 1 }
          return transaction.blockNumber - 2000
        }()
        self.fetchTransaction(for: address, startBlock: startBlock, completion: { [weak self] result in
          if case .success(let transactions) = result {
            self?.storage.add(transactions)
          }
        })
    })
  }

  func stopUpdatingAllTransactions() {
    self.allTxTimer?.invalidate()
    self.allTxTimer = nil
  }

  private func fetchTransaction(for address: Address, startBlock: Int, page: Int = 0, completion: @escaping (Result<[Transaction], AnyError>) -> Void) {
    NSLog("Fetch transactions from block \(startBlock) page \(page)")
    let trustProvider = TrustProviderFactory.makeProvider()
    trustProvider.request(.getTransactions(address: address.description, startBlock: startBlock, page: page)) { result in
      switch result {
      case .success(let response):
        do {
          _ = try response.filterSuccessfulStatusCodes()
          let rawTransactions = try response.map(ArrayResponse<RawTransaction>.self).docs
          let transactions: [Transaction] = rawTransactions.flatMap { .from(transaction: $0) }
          completion(.success(transactions))
        } catch let error {
          completion(.failure(AnyError(error)))
        }
      case .failure(let error):
        completion(.failure(AnyError(error)))
      }
    }
  }
}

// MARK: Pending transactions
extension KNTransactionCoordinator {
  func startUpdatingPendingTransactions() {
    self.pendingTxTimer?.invalidate()
    self.pendingTxTimer = nil
    self.shouldUpdatePendingTransaction(nil)
    self.pendingTxTimer = Timer.scheduledTimer(
      withTimeInterval: KNLoadingInterval.defaultLoadingInterval,
      repeats: true,
      block: { [weak self] timer in
      self?.shouldUpdatePendingTransaction(timer)
    })
  }

  @objc func shouldUpdatePendingTransaction(_ sender: Any?) {
    self.storage.pendingObjects.forEach { self.updatePendingTranscation($0) }
  }

  func updatePendingTranscation(_ transaction: Transaction) {
    self.checkTransactionReceipt(transaction) { [weak self] error in
      if error == nil { return }
      guard let `self` = self else { return }
      self.externalProvider.getTransactionByHash(transaction.id, completion: { [weak self] sessionError in
        guard let `self` = self else { return }
        if let trans = self.storage.get(forPrimaryKey: transaction.id), trans.state != .pending {
          // Prevent the notification is called multiple time due to timer runs
          return
        }
        if let error = sessionError {
          // Failure
          if case .responseError(let err) = error, let respError = err as? JSONRPCError {
            switch respError {
            case .responseError(let code, let message, _):
              NSLog("Fetch pending transaction with hash \(transaction.id) failed with error code \(code) and message \(message)")
              self.storage.delete([transaction])
            case .resultObjectParseError:
              if transaction.date.addingTimeInterval(60) < Date() {
                self.updateTransactionStateIfNeeded(transaction, state: .failed)
              }
            default: break
            }
          }
        } else {
          // Success
          if transaction.date.addingTimeInterval(60) < Date() {
            self.updateTransactionStateIfNeeded(transaction, state: .completed)
          }
        }
      })
    }
  }

  fileprivate func checkTransactionReceipt(_ transaction: Transaction, completion: @escaping (Error?) -> Void) {
    self.externalProvider.getReceipt(for: transaction) { [weak self] result in
      switch result {
      case .success(let newTx):
        if let trans = self?.storage.get(forPrimaryKey: newTx.id), trans.state != .pending {
          // Prevent the notification is called multiple time due to timer runs
          return
        }
        self?.storage.add([newTx])
        KNNotificationUtil.postNotification(
          for: kTransactionDidUpdateNotificationKey,
          object: newTx.id,
          userInfo: nil
        )
        completion(nil)
      case .failure(let error):
        completion(error)
      }
    }
  }

  fileprivate func updateTransactionStateIfNeeded(_ transaction: Transaction, state: TransactionState) {
    if let trans = self.storage.get(forPrimaryKey: transaction.id), trans.state != .pending { return }
    self.storage.update(state: state, for: transaction)
    KNNotificationUtil.postNotification(
      for: kTransactionDidUpdateNotificationKey,
      object: transaction.id,
      userInfo: nil
    )
  }

  func stopUpdatingPendingTransactions() {
    self.pendingTxTimer?.invalidate()
    self.pendingTxTimer = nil
  }
}

extension UnconfirmedTransaction {

  func toTransaction(wallet: Wallet, hash: String, nounce: Int) -> Transaction {
    let token: KNToken = self.transferType.knToken()

    let localObject = LocalizedOperationObject(
      from: token.address,
      to: "",
      contract: nil,
      type: "transfer",
      value: self.value.fullString(decimals: token.decimal),
      symbol: nil,
      name: nil,
      decimals: token.decimal
    )
    return Transaction(
      id: hash,
      blockNumber: 0,
      from: wallet.address.description,
      to: self.to?.description ?? "",
      value: self.value.fullString(decimals: token.decimal),
      gas: self.gasLimit?.fullString(units: UnitConfiguration.gasFeeUnit) ?? "",
      gasPrice: self.gasPrice?.fullString(units: UnitConfiguration.gasPriceUnit) ?? "",
      gasUsed: self.gasLimit?.fullString(units: UnitConfiguration.gasFeeUnit) ?? "",
      nonce: "\(nounce)",
      date: Date(),
      localizedOperations: [localObject],
      state: .pending
    )
  }
}
