// Copyright SIX DAY LLC. All rights reserved.

import BigInt

extension BigInt {

  func shortString(units: EthereumUnit, maxFractionDigits: Int = 5) -> String {
    let formatter = EtherNumberFormatter.short
    formatter.maximumFractionDigits = maxFractionDigits
    return formatter.string(from: self, units: units)
  }

  func shortString(decimals: Int, maxFractionDigits: Int = 5) -> String {
    let formatter = EtherNumberFormatter.short
    formatter.maximumFractionDigits = maxFractionDigits
    return formatter.string(from: self, decimals: decimals)
  }

  func fullString(units: EthereumUnit) -> String {
    return EtherNumberFormatter.full.string(from: self, units: units)
  }

  func fullString(decimals: Int) -> String {
    return EtherNumberFormatter.full.string(from: self, decimals: decimals)
  }
}
