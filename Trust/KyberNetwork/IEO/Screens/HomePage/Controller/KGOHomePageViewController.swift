// Copyright SIX DAY LLC. All rights reserved.

import UIKit
import WebKit

protocol KGOHomePageViewControllerDelegate: class {
  func kyberGOHomePageViewController(_ controller: KGOHomePageViewController, didSelect object: IEOObject)
}

class KGOHomePageViewController: KNBaseViewController {

  fileprivate var kIEOTableViewCellID: String = "kIEOTableViewCellID"
  fileprivate var kIEOTableViewHeaderID: String = "kIEOTableViewHeaderID"

  @IBOutlet weak var topContainerView: UIView!
  @IBOutlet weak var kyberGOLabel: UILabel!
  @IBOutlet weak var userAccountImageView: UIImageView!

  @IBOutlet weak var ieoTableView: UITableView!

  fileprivate var viewModel: KGOHomePageViewModel
  weak var delegate: KGOHomePageViewControllerDelegate?

  init(viewModel: KGOHomePageViewModel) {
    self.viewModel = viewModel
    super.init(nibName: KGOHomePageViewController.className, bundle: nil)
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    self.setupUI()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
  }

  fileprivate func setupUI() {
    self.setupTopView()
    self.setupIEOTableView()
  }

  fileprivate func setupTopView() {
    self.kyberGOLabel.text = "Kyber GO"
    self.userAccountImageView.rounded(radius: self.userAccountImageView.frame.width / 2.0)
    self.userAccountImageView.backgroundColor = UIColor(hex: "f5f5f5")
    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.accountImageViewDidTap(_:)))
    self.userAccountImageView.addGestureRecognizer(tapGesture)
    self.userAccountImageView.isUserInteractionEnabled = true
  }

  func setupIEOTableView() {
    let nib = UINib(nibName: KGOIEOTableViewCell.className, bundle: nil)
    self.ieoTableView.register(nib, forCellReuseIdentifier: kIEOTableViewCellID)
    self.ieoTableView.delegate = self
    self.ieoTableView.dataSource = self
    self.ieoTableView.rowHeight = 115
    self.ieoTableView.sectionHeaderHeight = 44
    self.ieoTableView.reloadData()
  }

  func coordinatorDidUpdateListKGO(_ objects: [IEOObject]) {
    self.viewModel.updateObjects(objects)
    self.ieoTableView.reloadData()
  }

  @objc func accountImageViewDidTap(_ sender: UITapGestureRecognizer) {
    let signInVC = KGOSignInViewController()
    signInVC.loadViewIfNeeded()
    signInVC.delegate = self
    self.present(signInVC, animated: true, completion: nil)
  }
}

extension KGOHomePageViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    self.delegate?.kyberGOHomePageViewController(
      self,
      didSelect: self.viewModel.object(for: indexPath.row, in: indexPath.section)
    )
  }
}

extension KGOHomePageViewController: UITableViewDataSource {
  func numberOfSections(in tableView: UITableView) -> Int {
    return self.viewModel.numberSections
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return self.viewModel.numberRows(for: section)
  }

  func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
    return UIView()
  }

  func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
    let view = UIView(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: 44))
    view.backgroundColor = UIColor(hex: "f5f5f5")
    let label = UILabel(frame: CGRect(x: 20.0, y: 0, width: tableView.frame.width - 40.0, height: 44))
    label.text = self.viewModel.headerTitle(for: section)
    label.font = UIFont.systemFont(ofSize: 20, weight: UIFont.Weight.medium)
    view.addSubview(label)
    return view
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: kIEOTableViewCellID, for: indexPath) as! KGOIEOTableViewCell
    let object = self.viewModel.object(for: indexPath.row, in: indexPath.section)
    let model = KGOIEOTableViewCellModel(object: object)
    cell.updateView(with: model)
    cell.delegate = self
    return cell
  }
}

extension KGOHomePageViewController: KGOIEOTableViewCellDelegate {
  func ieoTableViewCellBuyButtonPressed(for object: IEOObject, sender: KGOIEOTableViewCell) {
    //TODO:
  }

  func ieoTableViewCellShouldUpdateType(for object: IEOObject, sender: KGOIEOTableViewCell) {
    self.viewModel.updateObjects(self.viewModel.ieoObjects)
    self.ieoTableView.reloadData()
  }
}

extension KGOHomePageViewController: KGOSignInViewControllerDelegate {
  func kgoSignInViewController(_ controller: KGOSignInViewController, sendEvent event: KGOSignInViewEvent) {
    switch event {
    case .dismiss:
      self.dismiss(animated: true, completion: nil)
    default: return
    }
  }
}