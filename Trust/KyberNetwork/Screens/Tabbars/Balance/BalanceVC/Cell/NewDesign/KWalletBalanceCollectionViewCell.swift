// Copyright SIX DAY LLC. All rights reserved.

import UIKit
import BigInt

struct KWalletBalanceCollectionViewCellModel {
  let token: TokenObject
  let trackerRate: KNTrackerRate?
  let balance: Balance?
  let currencyType: KWalletCurrencyType
  let index: Int

  init(
    token: TokenObject,
    trackerRate: KNTrackerRate?,
    balance: Balance?,
    currencyType: KWalletCurrencyType,
    index: Int
    ) {
    self.token = token
    self.trackerRate = trackerRate
    self.balance = balance
    self.currencyType = currencyType
    self.index = index
  }

  var backgroundColor: UIColor {
    return self.index % 2 == 0 ? .white : UIColor(red: 246, green: 247, blue: 250)
  }

  var displaySymbolAndNameAttributedString: NSAttributedString {
    let attributedString = NSMutableAttributedString()
    let symbolAttributes: [NSAttributedStringKey: Any] = [
      NSAttributedStringKey.font: UIFont.Kyber.medium(with: 16),
      NSAttributedStringKey.foregroundColor: UIColor(red: 29, green: 48, blue: 58),
      NSAttributedStringKey.kern: 1.0,
    ]
    let nameAttributes: [NSAttributedStringKey: Any] = [
      NSAttributedStringKey.font: UIFont.Kyber.regular(with: 12),
      NSAttributedStringKey.foregroundColor: UIColor(red: 158, green: 161, blue: 170),
      NSAttributedStringKey.kern: 1.0,
    ]
    attributedString.append(NSAttributedString(string: self.token.symbol, attributes: symbolAttributes))
    attributedString.append(NSAttributedString(string: " - \(self.token.name)", attributes: nameAttributes))
    return attributedString
  }

  var displayRateString: String {
    let rate: BigInt? = {
      if self.currencyType == .usd {
        if let trackerRate = self.trackerRate {
          return KNRate.rateUSD(from: trackerRate).rate
        }
        return nil
      }
      if let trackerRate = self.trackerRate {
        return KNRate.rateETH(from: trackerRate).rate
      }
      return nil
    }()
    guard let rateValue = rate else { return "---" }
    let rateString = rateValue.string(units: .ether, minFractionDigits: 0, maxFractionDigits: 6).prefix(11)
    return "\(rateString.prefix(11)) \(self.currencyType.rawValue)"
  }

  var displayAmountHoldingsText: String {
    return self.balance?.value.string(decimals: self.token.decimals, minFractionDigits: 0, maxFractionDigits: 6) ?? "---"
  }

  fileprivate var displayBalanceValue: String {
    return self.currencyType == .usd ? self.displayBalanceInUSD : self.displayBalanceInETH
  }

  fileprivate var displayBalanceInUSD: String {
    if let amount = self.balance?.value, let trackerRate = self.trackerRate {
      let rate = KNRate.rateUSD(from: trackerRate)
      let value = (amount * rate.rate / BigInt(10).power(self.token.decimals)).string(units: .ether, minFractionDigits: 0, maxFractionDigits: 6)
      return "\(value.prefix(11)) \(self.currencyType.rawValue)"
    }
    return "---"
  }

  fileprivate var displayBalanceInETH: String {
    if let amount = self.balance?.value, let trackerRate = self.trackerRate {
      let rate = KNRate.rateETH(from: trackerRate)
      let value = (amount * rate.rate / BigInt(10).power(self.token.decimals)).string(units: .ether, minFractionDigits: 0, maxFractionDigits: 9)
      return "\(value.prefix(11)) \(self.currencyType.rawValue)"
    }
    return "---"
  }
}

class KWalletBalanceCollectionViewCell: UICollectionViewCell {

  static let cellID: String = "KWalletBalanceCollectionViewCell"
  static let cellHeight: CGFloat = 64

  @IBOutlet weak var iconImageView: UIImageView!
  @IBOutlet weak var symbolLabel: UILabel!
  @IBOutlet weak var rateLabel: UILabel!
  @IBOutlet weak var amountHoldingsLabel: UILabel!
  @IBOutlet weak var valueLabel: UILabel!

  override func awakeFromNib() {
    super.awakeFromNib()
    // Initialization code
    self.iconImageView.image = nil
    self.symbolLabel.text = ""
    self.rateLabel.text = ""
    self.amountHoldingsLabel.text = ""
    self.valueLabel.text = ""
    self.iconImageView.rounded(radius: self.iconImageView.frame.width / 2.0)
  }

  func updateCellView(with viewModel: KWalletBalanceCollectionViewCellModel) {
    self.iconImageView.setTokenImage(
      token: viewModel.token,
      size: self.iconImageView.frame.size
    )
//    self.symbolLabel.text = viewModel.token.symbol
    self.symbolLabel.attributedText = viewModel.displaySymbolAndNameAttributedString
    self.rateLabel.text = viewModel.displayRateString
    self.amountHoldingsLabel.text = viewModel.displayAmountHoldingsText
    self.valueLabel.text = viewModel.displayBalanceValue
    self.backgroundColor = viewModel.backgroundColor
  }
}
