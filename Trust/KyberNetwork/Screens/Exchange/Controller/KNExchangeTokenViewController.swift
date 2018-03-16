// Copyright SIX DAY LLC. All rights reserved.

import UIKit
import BigInt
import Result

// TODO: Handle for all actions that could lead to change data

protocol KNExchangeTokenViewControllerDelegate: class {
  func exchangeTokenAmountDidChange(source: KNToken, dest: KNToken, amount: BigInt)
  func exchangeTokenShouldUpdateEstimateGasUsed(exchangeTransaction: KNDraftExchangeTransaction)
  func exchangeTokenDidClickExchange(exchangeTransaction: KNDraftExchangeTransaction, expectedRate: BigInt)
  func exchangeTokenUserDidClickSelectTokenButton(source: KNToken, dest: KNToken, isSource: Bool)
  func exchangeTokenUserDidClickExit()
}

class KNExchangeTokenViewController: UIViewController {

  fileprivate let advancedSettingsHeight: CGFloat = 150
  fileprivate let exchangeButtonTopPaddingiPhone5: CGFloat = 40
  fileprivate let exchangeButtonTopPaddingiPhone6: CGFloat = 220
  fileprivate let exchangeButtonTopPaddingiPhone6Plus: CGFloat = 250

  fileprivate weak var delegate: KNExchangeTokenViewControllerDelegate?

  fileprivate let ethToken: KNToken = KNToken.ethToken()
  fileprivate let kncToken: KNToken = KNToken.kncToken()

  fileprivate var selectedFromToken: KNToken!
  fileprivate var selectedToToken: KNToken!

  fileprivate var isFocusingFromTokenAmount: Bool = true

  fileprivate var expectedRateTimer: Timer?
  fileprivate var ethBalance: Balance?
  fileprivate var otherTokenBalances: [String: Balance] = [:]

  fileprivate var lastEstimateGasUsed: BigInt = BigInt(0)

  fileprivate var expectedRate: BigInt = BigInt(0)
  fileprivate var slippageRate: BigInt = BigInt(0)
  fileprivate var userDidChangeMinRate: Bool = false

  @IBOutlet weak var scrollContainerView: UIScrollView!

  @IBOutlet weak var fromTokenLabel: UILabel!
  @IBOutlet weak var fromTokenButton: UIButton!
  @IBOutlet weak var fromTokenBalanceLabel: UILabel!
  @IBOutlet weak var amountFromTokenLabel: UILabel!
  @IBOutlet weak var amountFromTokenTextField: UITextField!

  @IBOutlet var percentageButtons: [UIButton]!

  @IBOutlet weak var toTokenLabel: UILabel!
  @IBOutlet weak var toTokenButton: UIButton!
  @IBOutlet weak var toTokenBalanceLabel: UILabel!

  @IBOutlet weak var amounToTokenLabel: UILabel!
  @IBOutlet weak var amountToTokenTextField: UITextField!

  @IBOutlet weak var heightForAdvancedSettingsView: NSLayoutConstraint!
  @IBOutlet weak var advancedSettingsView: UIView!
  @IBOutlet weak var minRateTextField: UITextField!
  @IBOutlet weak var gasPriceTextField: UITextField!
  @IBOutlet weak var lowGasPriceButton: UIButton!
  @IBOutlet weak var standardGasPriceButton: UIButton!
  @IBOutlet weak var fastGasPriceButton: UIButton!
  @IBOutlet weak var transactionFeeLabel: UILabel!

  @IBOutlet weak var topPaddingConstraintForExchangeButton: NSLayoutConstraint!
  @IBOutlet weak var advancedLabel: UILabel!
  @IBOutlet weak var advancedSwitch: UISwitch!
  @IBOutlet weak var expectedRateLabel: UILabel!
  @IBOutlet weak var exchangeButton: UIButton!

  init(delegate: KNExchangeTokenViewControllerDelegate?) {
    self.delegate = delegate
    super.init(nibName: KNExchangeTokenViewController.className, bundle: nil)
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    self.setupUI()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    NSLog("Did open: \(self.className)")
    self.expectedRateTimer?.invalidate()
    self.expectedRateTimer = nil
    self.expectedRateTimerShouldRepeat(nil)
    self.expectedRateTimer = Timer.scheduledTimer(timeInterval: 10.0, target: self, selector: #selector(self.expectedRateTimerShouldRepeat(_:)), userInfo: nil, repeats: true)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    self.expectedRateTimer?.invalidate()
    self.expectedRateTimer = nil
  }
}

// MARK: Setup view
extension KNExchangeTokenViewController {
  fileprivate func setupUI() {
    self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Exit", style: .plain, target: self, action: #selector(self.exitButtonPressed(_:)))
    self.navigationItem.leftBarButtonItem?.tintColor = UIColor.white
    self.setupInitialData()
    self.setupFromToken()
    self.setupToToken()
    self.setupAdvancedSettingsView()
    self.setupExchangeButton()
    self.view.updateConstraints()
  }

  fileprivate func setupInitialData() {
    self.selectedFromToken = self.ethToken
    self.selectedToToken = self.kncToken
    self.updateRates()
    self.lastEstimateGasUsed = KNGasConfiguration.exchangeTokensGasLimitDefault
  }

  fileprivate func setupFromToken() {
    self.fromTokenLabel.text = "From".toBeLocalised()
    self.fromTokenButton.rounded(color: UIColor.white, width: 1.0, radius: 10.0)

    self.amountFromTokenLabel.text = "Amount".toBeLocalised()
    self.amountFromTokenTextField.text = "0"
    self.amountFromTokenTextField.delegate = self

    for button in self.percentageButtons { button.rounded(color: .clear, width: 0, radius: 4.0) }
    self.updateFromTokenWhenTokenDidChange()
  }

  fileprivate func setupToToken() {
    self.toTokenLabel.text = "To".toBeLocalised()
    self.toTokenButton.rounded(color: UIColor.white, width: 1.0, radius: 10.0)

    self.amountToTokenTextField.text = "0"
    self.amountToTokenTextField.delegate = self

    self.updateToTokenWhenTokenDidChange()
  }

  fileprivate func setupAdvancedSettingsView() {
    self.minRateTextField.text = self.slippageRate.fullString(decimals: self.selectedToToken.decimal)
    self.minRateTextField.delegate = self

    self.gasPriceTextField.text = "\(KNGasCoordinator.shared.defaultKNGas)"
    self.gasPriceTextField.delegate = self

    self.lowGasPriceButton.setTitle("Low".toBeLocalised(), for: .normal)
    self.lowGasPriceButton.rounded(color: .clear, width: 0, radius: 4.0)

    self.standardGasPriceButton.setTitle("Standard".toBeLocalised(), for: .normal)
    self.standardGasPriceButton.rounded(color: .clear, width: 0, radius: 4.0)

    self.fastGasPriceButton.setTitle("Fast".toBeLocalised(), for: .normal)
    self.fastGasPriceButton.rounded(color: .clear, width: 0, radius: 4.0)

    let fee = BigInt(KNGasCoordinator.shared.defaultKNGas) * self.lastEstimateGasUsed
    let feeString = fee.shortString(units: UnitConfiguration.gasFeeUnit)

    self.transactionFeeLabel.text = "Transaction Fee: \(feeString) ETH".toBeLocalised()
    self.advancedLabel.text = "Advanced".toBeLocalised()

    self.heightForAdvancedSettingsView.constant = 0
    self.advancedSettingsView.isHidden = true
  }

  fileprivate func setupExchangeButton() {
    let rateString = self.expectedRate.shortString(decimals: self.selectedToToken.decimal)
    self.expectedRateLabel.text = "1 \(self.selectedFromToken.symbol) = \(rateString) \(self.selectedToToken.symbol)"

    self.exchangeButton.setTitle("Exchange".toBeLocalised(), for: .normal)
    self.exchangeButton.rounded(color: .clear, width: 0, radius: 5.0)

    self.topPaddingConstraintForExchangeButton.constant = UIDevice.isIphone5 ? exchangeButtonTopPaddingiPhone5 : exchangeButtonTopPaddingiPhone6
  }
}

// MARK: Update data
extension KNExchangeTokenViewController {
  fileprivate func updateFromToken(_ token: KNToken) {
    self.selectedFromToken = token
    self.userDidChangeMinRate = false
    self.updateRates()
    self.updateFromTokenWhenTokenDidChange()
  }

  fileprivate func updateToToken(_ token: KNToken) {
    self.selectedToToken = token
    self.userDidChangeMinRate = false
    self.updateRates()
    self.updateToTokenWhenTokenDidChange()
  }

  fileprivate func updateRates() {
    if let rate = KNRateCoordinator.shared.tokenRates.first(where: {
      $0.source == self.selectedFromToken.symbol && $0.dest == self.selectedToToken.symbol
    }) {
      self.expectedRate = rate.rate
      self.slippageRate = rate.minRate
    }
    self.updateViewWhenRatesDidChange()
  }

  fileprivate func updateEstimateGasUsed(_ estimateGas: BigInt) {
    self.lastEstimateGasUsed = estimateGas
    self.updateTransactionFee()
  }
}

// MARK: Update view
extension KNExchangeTokenViewController {
  fileprivate func updateFromTokenWhenTokenDidChange() {
    self.fromTokenButton.setTitle("\(self.selectedFromToken.display)", for: .normal)
    let balanceString = self.otherTokenBalances[self.selectedFromToken.address]?.amountShort ?? "0.0000"
    self.fromTokenBalanceLabel.text = "Balance: \(balanceString) \(self.selectedFromToken.symbol)".toBeLocalised()
    self.amountFromTokenTextField.text = "0"
    self.amountToTokenTextField.text = "0"
  }

  fileprivate func updateToTokenWhenTokenDidChange() {
    self.toTokenButton.setTitle("\(self.selectedToToken.display)", for: .normal)
    let balanceString = self.otherTokenBalances[self.selectedToToken.address]?.amountShort ?? "0.0000"
    self.toTokenBalanceLabel.text = "Balance: \(balanceString) \(self.selectedToToken.symbol)".toBeLocalised()
    self.amountFromTokenTextField.text = "0"
    self.amountToTokenTextField.text = "0"
  }

  fileprivate func updateTransactionFee() {
    var gasPrice = KNGasConfiguration.gasPriceDefault
    if let gasPriceBigInt = self.gasPriceTextField.text?.fullBigInt(units: UnitConfiguration.gasPriceUnit) {
      gasPrice = gasPriceBigInt
    }
    let fee = gasPrice * self.lastEstimateGasUsed
    self.transactionFeeLabel.text = "Transaction Fee: \(fee.shortString(units: EthereumUnit.ether)) ETH"
  }

  fileprivate func updateViewWhenRatesDidChange() {
    if !self.userDidChangeMinRate {
      self.minRateTextField.text = self.slippageRate.fullString(decimals: self.selectedToToken.decimal)
    }

    self.expectedRateLabel.text = "1 \(self.selectedFromToken.symbol) = \(self.expectedRate.shortString(decimals: self.selectedToToken.decimal)) \(self.selectedToToken.symbol)"
    if self.isFocusingFromTokenAmount {
      let amount = self.amountFromTokenTextField.text?.fullBigInt(decimals: self.selectedFromToken.decimal) ?? BigInt(0)
      let expectedAmount = self.expectedRate * amount / BigInt(10).power(self.selectedToToken.decimal)
      self.amountToTokenTextField.text = expectedAmount.shortString(decimals: self.selectedToToken.decimal)
    } else {
      let expectedAmount = self.amountToTokenTextField.text?.fullBigInt(decimals: self.selectedToToken.decimal) ?? BigInt(0)
      let value = self.expectedRate.isZero ? BigInt(0) : expectedAmount * BigInt(10).power(self.selectedFromToken.decimal) / self.expectedRate
      self.amountFromTokenTextField.text = value.shortString(decimals: self.selectedFromToken.decimal)
    }
  }

  fileprivate func updateViewWhenBalancesDidChange() {
    let sourceBalance = self.otherTokenBalances[self.selectedFromToken.address]?.amountShort ?? "0.0000"
    self.fromTokenBalanceLabel.text = "Balance: \(sourceBalance) \(self.selectedFromToken.symbol)".toBeLocalised()
    let destBalance = self.otherTokenBalances[self.selectedToToken.address]?.amountShort ?? "0.0000"
    self.toTokenBalanceLabel.text = "Balance: \(destBalance) \(self.selectedToToken.symbol)".toBeLocalised()
  }
}
// MARK: Update data from coordinator
extension KNExchangeTokenViewController {
  // TODO (Mike): Should be removed
  func updateBalance(usd: BigInt, eth: BigInt) {
    self.navigationItem.title = "$\(EtherNumberFormatter.short.string(from: usd))"
    self.view.layoutIfNeeded()
  }

  func updateSelectedToken(_ token: KNToken, isSource: Bool) {
    if isSource {
      if self.selectedFromToken == token { return }
      self.updateFromToken(token)
      self.updateToToken(token.isETH ? self.kncToken : self.ethToken)
    } else {
      if self.selectedToToken == token { return }
      self.updateToToken(token)
      self.updateFromToken(token.isETH ? self.kncToken : self.ethToken)
    }
  }

  func ethBalanceDidUpdate(balance: Balance) {
    self.ethBalance = balance
    self.otherTokenBalances[self.ethToken.address] = balance
    self.updateViewWhenBalancesDidChange()
  }

  func otherTokenBalanceDidUpdate(balances: [String: Balance]) {
    self.otherTokenBalances = balances
    self.otherTokenBalances[self.ethToken.address] = self.ethBalance
    self.updateViewWhenBalancesDidChange()
  }

  func updateEstimateRateDidChange(source: KNToken, dest: KNToken, amount: BigInt, expectedRate: BigInt, slippageRate: BigInt) {
    if source != self.selectedFromToken || dest != self.selectedToToken { return }
    self.expectedRate = expectedRate
    self.slippageRate = slippageRate
    self.updateViewWhenRatesDidChange()
  }

  func updateEstimateGasUsed(source: KNToken, dest: KNToken, amount: BigInt, estimate: BigInt) {
    if source != self.selectedFromToken || dest != self.selectedToToken { return }
    self.updateEstimateGasUsed(estimate)
  }

  func exchangeTokenDidReturn(result: Result<String, AnyError>) {
    switch result {
    case .success(let txID):
      self.displaySuccess(title: "Transaction Sent", message: txID)
    case .failure(let error):
      self.displayError(error: error)
    }
  }
}

// MARK: Helpers & Buttons handlers
extension KNExchangeTokenViewController {
  fileprivate func validateData(completion: (Result<KNDraftExchangeTransaction?, AnyError>) -> Void) {
    guard
      let amount = self.amountFromTokenTextField.text?.fullBigInt(decimals: self.selectedFromToken.decimal),
      let balance = self.otherTokenBalances[self.selectedFromToken.address],
      amount <= balance.value else {
        completion(.success(nil))
        return
    }
    guard let gasPrice = self.gasPriceTextField.text?.fullBigInt(units: UnitConfiguration.gasPriceUnit) else {
      completion(.success(nil))
      return
    }
    if (self.minRateTextField.text ?? "0").fullBigInt(decimals: self.selectedToToken.decimal) == nil {
      completion(.success(nil))
      return
    }
    let exchange = KNDraftExchangeTransaction(
      from: self.selectedFromToken,
      to: self.selectedToToken,
      amount: amount,
      maxDestAmount: BigInt(2).power(255),
      minRate: self.minRateTextField.text?.fullBigInt(decimals: self.selectedToToken.decimal) ?? self.slippageRate,
      gasPrice: gasPrice,
      gasLimit: self.lastEstimateGasUsed
    )
    completion(.success(exchange))
  }

  fileprivate func shouldUpdateEstimateGasUsed(_ sender: Any?) {
    let amount = self.amountFromTokenTextField.text?.fullBigInt(decimals: self.selectedFromToken.decimal) ?? BigInt(0)
    let exchange = KNDraftExchangeTransaction(
      from: self.selectedFromToken,
      to: self.selectedToToken,
      amount: amount,
      maxDestAmount: BigInt(2).power(255),
      minRate: .none,
      gasPrice: .none,
      gasLimit: .none
    )
    self.delegate?.exchangeTokenShouldUpdateEstimateGasUsed(exchangeTransaction: exchange)
  }

  @objc func expectedRateTimerShouldRepeat(_ sender: Any?) {
    let amount = self.amountFromTokenTextField.text?.fullBigInt(decimals: self.selectedFromToken.decimal) ?? BigInt(0)
    self.delegate?.exchangeTokenAmountDidChange(
      source: self.selectedFromToken,
      dest: self.selectedToToken,
      amount: amount
    )
  }

  @objc func exitButtonPressed(_ sender: Any) {
    self.delegate?.exchangeTokenUserDidClickExit()
  }

  @IBAction func fromTokenButtonPressed(_ sender: Any) {
    self.delegate?.exchangeTokenUserDidClickSelectTokenButton(
      source: self.selectedFromToken,
      dest: self.selectedToToken,
      isSource: true
    )
  }

  @IBAction func percentageButtonPressed(_ sender: UIButton) {
    self.isFocusingFromTokenAmount = true
    let percent = sender.tag
    let balance: Balance = self.otherTokenBalances[self.selectedFromToken.address] ?? Balance(value: BigInt(0))
    let amount: BigInt = balance.value * BigInt(percent) / BigInt(100)
    self.amountFromTokenTextField.text = amount.shortString(decimals: self.selectedFromToken.decimal)
    self.view.layoutIfNeeded()
    self.expectedRateTimerShouldRepeat(sender)
    self.shouldUpdateEstimateGasUsed(sender)
  }

  @IBAction func toTokenButtonPressed(_ sender: Any) {
    self.delegate?.exchangeTokenUserDidClickSelectTokenButton(
      source: self.selectedFromToken,
      dest: self.selectedToToken,
      isSource: false
    )
  }

  @IBAction func advancedSwitchDidChange(_ sender: Any) {
    if self.advancedSwitch.isOn {
      self.advancedSettingsView.isHidden = false
      self.heightForAdvancedSettingsView.constant = advancedSettingsHeight
      self.topPaddingConstraintForExchangeButton.constant = exchangeButtonTopPaddingiPhone6
    } else {
      self.advancedSettingsView.isHidden = true
      self.heightForAdvancedSettingsView.constant = 0
      self.topPaddingConstraintForExchangeButton.constant = UIDevice.isIphone5 ? exchangeButtonTopPaddingiPhone5 : exchangeButtonTopPaddingiPhone6
    }
    self.view.updateConstraints()
  }

  @IBAction func lowGasPriceButtonPressed(_ sender: Any) {
    self.gasPriceTextField.text = "\(KNGasCoordinator.shared.lowKNGas)"
    self.updateTransactionFee()
  }

  @IBAction func standardGasPriceButtonPressed(_ sender: Any) {
    self.gasPriceTextField.text = "\(KNGasCoordinator.shared.standardKNGas)"
    self.updateTransactionFee()
  }

  @IBAction func fastGasPriceButtonPressed(_ sender: Any) {
    self.gasPriceTextField.text = "\(KNGasCoordinator.shared.fastKNGas)"
    self.updateTransactionFee()
  }

  @IBAction func exchangeButtonPressed(_ sender: Any) {
    self.validateData { [weak self] result in
      guard let `self` = self else { return }
      switch result {
      case .success(let exchangeTransaction):
        if let exchange = exchangeTransaction {
          self.delegate?.exchangeTokenDidClickExchange(exchangeTransaction: exchange, expectedRate: self.expectedRate)
        } else {
          let alertController = UIAlertController(title: nil, message: "Invalid exchange data", preferredStyle: .alert)
          alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
          self.present(alertController, animated: true, completion: nil)
        }
      case .failure(let error):
        self.displayError(error: error)
      }
    }
  }
}

// MARK: Delegations
extension KNExchangeTokenViewController: UITextFieldDelegate {
  func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
    let text = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
    textField.text = text
    if textField == self.amountFromTokenTextField {
      self.isFocusingFromTokenAmount = true
    } else if textField == self.amountToTokenTextField {
      self.isFocusingFromTokenAmount = false
    } else if textField == self.gasPriceTextField {
      self.updateTransactionFee()
    } else if textField == self.minRateTextField {
      self.userDidChangeMinRate = true
    }
    self.shouldUpdateEstimateGasUsed(textField)
    self.expectedRateTimerShouldRepeat(textField)
    return false
  }
}
