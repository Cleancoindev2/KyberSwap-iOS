// Copyright SIX DAY LLC. All rights reserved.

import Foundation
import Result
import Moya
import JSONRPCKit
import APIKit
import BigInt
import TrustKeystore
import TrustCore

class KNGasCoordinator {

  static let shared: KNGasCoordinator = KNGasCoordinator()
  fileprivate let provider = MoyaProvider<KyberNetworkService>()

  lazy var numberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    return formatter
  }()

  var defaultKNGas: BigInt = KNGasConfiguration.gasPriceDefault
  var standardKNGas: BigInt = KNGasConfiguration.gasPriceDefault
  var lowKNGas: BigInt = KNGasConfiguration.gasPriceMin
  var fastKNGas: BigInt = KNGasConfiguration.gasPriceMax
  var superFastKNGas: BigInt {
    if fastKNGas < EtherNumberFormatter.full.number(from: "10", units: UnitConfiguration.gasPriceUnit)! {
      return KNGasConfiguration.gasPriceMax // 20 gwei
    }
    let maxGas = EtherNumberFormatter.full.number(from: "100", units: UnitConfiguration.gasPriceUnit)!
    return min(fastKNGas * BigInt(2), maxGas)
  }

  var maxKNGas: BigInt = KNGasConfiguration.gasPriceMax

  fileprivate var knGasPriceFetchTimer: Timer?
  fileprivate var isLoadingGasPrice: Bool = false

  init() {}

  func resume() {
    knGasPriceFetchTimer?.invalidate()
    isLoadingGasPrice = false
    fetchKNGasPrice(nil)

    knGasPriceFetchTimer = Timer.scheduledTimer(
      timeInterval: KNLoadingInterval.defaultLoadingInterval,
      target: self,
      selector: #selector(fetchKNGasPrice(_:)),
      userInfo: nil,
      repeats: true
    )
  }

  func pause() {
    knGasPriceFetchTimer?.invalidate()
    knGasPriceFetchTimer = nil
    isLoadingGasPrice = true
  }

  @objc func fetchKNGasPrice(_ sender: Timer?) {
    if isLoadingGasPrice { return }
    isLoadingGasPrice = true
    DispatchQueue.global(qos: .background).async {
      KNInternalProvider.shared.getKNCachedGasPrice { [weak self] (result) in
        guard let `self` = self else { return }
        DispatchQueue.main.async {
          self.isLoadingGasPrice = false
          if case .success(let data) = result {
            try? self.updateGasPrice(dataJSON: data)
          }
        }
      }
    }
  }

  fileprivate func updateGasPrice(dataJSON: JSONDictionary) throws {
    guard let data = dataJSON["data"] as? JSONDictionary else { return }
    let stringDefault: String = data["default"] as? String ?? ""
    self.defaultKNGas = stringDefault.shortBigInt(units: UnitConfiguration.gasPriceUnit) ?? self.defaultKNGas
    let stringLow: String = data["low"] as? String ?? ""
    self.lowKNGas = stringLow.shortBigInt(units: UnitConfiguration.gasPriceUnit) ?? self.lowKNGas
    let stringStandard: String = data["standard"] as? String ?? ""
    self.standardKNGas = stringStandard.shortBigInt(units: UnitConfiguration.gasPriceUnit) ?? self.standardKNGas
    let stringFast: String = data["fast"] as? String ?? ""
    self.fastKNGas = stringFast.shortBigInt(units: UnitConfiguration.gasPriceUnit) ?? self.fastKNGas
    KNNotificationUtil.postNotification(for: kGasPriceDidUpdateNotificationKey)
  }
}
