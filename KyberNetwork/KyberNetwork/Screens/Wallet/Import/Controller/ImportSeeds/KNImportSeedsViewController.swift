// Copyright SIX DAY LLC. All rights reserved.

import UIKit
import TrustKeystore
import TrustCore

protocol KNImportSeedsViewControllerDelegate: class {
  func importSeedsViewControllerDidPressNext(sender: KNImportSeedsViewController, seeds: [String], name: String?)
}

class KNImportSeedsViewController: KNBaseViewController {

  weak var delegate: KNImportSeedsViewControllerDelegate?
  fileprivate let numberWords: Int = 12

  @IBOutlet weak var recoverSeedsLabel: UILabel!
  @IBOutlet weak var descLabel: UILabel!
  @IBOutlet weak var seedsTextField: UITextField!
  @IBOutlet weak var walletNameTextField: UITextField!
  @IBOutlet weak var wordsCountLabel: UILabel!

  @IBOutlet weak var nextButton: UIButton!

  override func viewDidLoad() {
    super.viewDidLoad()
    self.seedsTextField.delegate = self

    self.recoverSeedsLabel.text = NSLocalizedString("recover.with.seeds", value: "Recover with seeds", comment: "")
    let style = KNAppStyleType.current
    self.nextButton.rounded(radius: style.buttonRadius(for: self.nextButton.frame.height))
    self.nextButton.setBackgroundColor(
      style.importWalletButtonDisabledColor,
      forState: .disabled
    )
    self.nextButton.setBackgroundColor(
      style.importWalletButtonEnabledColor,
      forState: .normal
    )
    self.nextButton.setTitle(
      NSLocalizedString("import.wallet", value: "Import Wallet", comment: ""),
      for: .normal
    )
    self.seedsTextField.placeholder = NSLocalizedString("enter.your.seeds", value: "Enter your seeds", comment: "")
    self.walletNameTextField.placeholder = NSLocalizedString("name.of.your.wallet.optional", value: "Name of your wallet (optional)", comment: "")

    self.resetUIs()
  }

  func resetUIs() {
    self.seedsTextField.text = ""
    self.wordsCountLabel.text = "\(NSLocalizedString("words.count", value: "Words Count", comment: "")): 0"
    self.walletNameTextField.text = ""
    self.updateNextButton()
  }

  fileprivate func updateNextButton() {
    let enabled: Bool = {
      guard let seeds = self.seedsTextField.text?.trimmed else { return false }
      var words = seeds.components(separatedBy: " ").map({ $0.trimmed })
      words = words.filter({ !$0.replacingOccurrences(of: " ", with: "").isEmpty })
      return words.count == self.numberWords
    }()
    self.nextButton.isEnabled = enabled
  }

  @IBAction func nextButtonPressed(_ sender: Any) {
    if let seeds = self.seedsTextField.text?.trimmed {
      guard Mnemonic.isValid(seeds) else {
        self.parent?.showErrorTopBannerMessage(
          with: NSLocalizedString("invalid.seeds", value: "Invalid Seeds", comment: ""),
          message: NSLocalizedString("please.check.your.seeds.again", value: "Please check your seeds again", comment: "")
        )
        return
      }
      var words = seeds.components(separatedBy: " ").map({ $0.trimmed })
      words = words.filter({ !$0.replacingOccurrences(of: " ", with: "").isEmpty })
      if words.count == self.numberWords {
        self.delegate?.importSeedsViewControllerDidPressNext(
          sender: self,
          seeds: words.map({ return String($0) }),
          name: self.walletNameTextField.text
        )
      } else {
        self.parent?.showErrorTopBannerMessage(
          with: NSLocalizedString("invalid.seeds", value: "Invalid Seeds", comment: ""),
          message: NSLocalizedString("seeds.should.have.exactly.12.words", value: "Seeds should have exactly 12 words", comment: "")
        )
      }
    } else {
      self.parent?.showErrorTopBannerMessage(
        with: NSLocalizedString("field.required", value: "Field Required", comment: ""),
        message: NSLocalizedString("please.check.your.input.data", value: "Please check your input data", comment: ""))
    }
  }
}

extension KNImportSeedsViewController: UITextFieldDelegate {
  func textFieldShouldClear(_ textField: UITextField) -> Bool {
    textField.text = ""
    if textField == self.seedsTextField {
      self.wordsCountLabel.text = "\(NSLocalizedString("words.count", value: "Words Count", comment: "")): 0"
      self.updateNextButton()
    }
    return false
  }
  func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
    let text = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
    textField.text = text
    if textField == self.seedsTextField {
      var words = text.trimmed.components(separatedBy: " ").map({ $0.trimmed })
      words = words.filter({ !$0.replacingOccurrences(of: " ", with: "").isEmpty })
      self.wordsCountLabel.text = "\(NSLocalizedString("words.count", value: "Words Count", comment: "")): \(words.count)"
      self.updateNextButton()
    }
    return false
  }
}