// Copyright SIX DAY LLC. All rights reserved.

import UIKit
import RealmSwift
import TrustKeystore

// "ERC20 - Token Transfer Events" by Address
class KNTokenTransaction: Object {

  @objc dynamic var id: String = ""
  @objc dynamic var blockNumber: Int = 0
  @objc dynamic var date: Date = Date()
  @objc dynamic var nonce: String = ""
  @objc dynamic var blockHash: String = ""
  @objc dynamic var from: String = ""
  @objc dynamic var contractAddress: String = ""
  @objc dynamic var to: String = ""
  @objc dynamic var value: String = ""
  @objc dynamic var tokenName: String = ""
  @objc dynamic var tokenSymbol: String = ""
  @objc dynamic var tokenDecimal: String = ""
  @objc dynamic var transactionIndex: String = ""
  @objc dynamic var gas: String = ""
  @objc dynamic var gasPrice: String = ""
  @objc dynamic var gasUsed: String = ""
  @objc dynamic var cumulativeGasUsed: String = ""
  @objc dynamic var input: String = ""
  @objc dynamic var confirmations: String = ""

  convenience init(dictionary: JSONDictionary) {
    self.init()
    self.id = dictionary["hash"] as? String ?? ""
    let blockNumberString: String = dictionary["blockNumber"] as? String ?? ""
    self.blockNumber = Int(blockNumberString) ?? 0
    let timeStamp: String = dictionary["timeStamp"]  as? String ?? ""
    self.date = Date(timeIntervalSince1970: Double(timeStamp) ?? 0.0)
    self.nonce = dictionary["nonce"] as? String ?? ""
    self.blockHash = dictionary["blockHash"] as? String ?? ""
    self.from = dictionary["from"] as? String ?? ""
    self.contractAddress = dictionary["contractAddress"] as? String ?? ""
    self.to = dictionary["to"] as? String ?? ""
    self.value = dictionary["value"] as? String ?? ""
    self.tokenName = dictionary["tokenName"] as? String ?? ""
    self.tokenSymbol = dictionary["tokenSymbol"] as? String ?? ""
    self.tokenDecimal = dictionary["tokenDecimal"] as? String ?? ""
    self.transactionIndex = dictionary["transactionIndex"] as? String ?? ""
    self.gas = dictionary["gas"] as? String ?? ""
    self.gasPrice = dictionary["gasPrice"] as? String ?? ""
    self.gasUsed = dictionary["gasUsed"] as? String ?? ""
    self.cumulativeGasUsed = dictionary["cumulativeGasUsed"] as? String ?? ""
    self.input = dictionary["input"] as? String ?? ""
    self.confirmations = dictionary["confirmations"] as? String ?? ""
  }

  override static func primaryKey() -> String? {
    return "id"
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let object = object as? KNTokenTransaction else { return false }
    return object.id == self.id
  }
}

extension KNTokenTransaction {
  func getToken() -> TokenObject? {
    guard let _ = Address(string: self.contractAddress) else { return nil }
    return TokenObject(
      contract: self.contractAddress,
      name: self.tokenName,
      symbol: self.tokenSymbol,
      decimals: Int(self.tokenDecimal) ?? 18,
      value: "0",
      isCustom: false,
      isDisabled: false
    )
  }
}
