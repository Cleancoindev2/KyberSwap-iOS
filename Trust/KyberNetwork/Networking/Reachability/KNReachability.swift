// Copyright SIX DAY LLC. All rights reserved.

import Alamofire
import NotificationCenter

class KNReachability: NSObject {

  static let kNetworkReachableNotificationKey: String = "kNetworkReachableNotificationKey"
  static let kNetworkUnreachableNotificationKey: String = "kNetworkUnreachableNotificationKey"

  static let shared = KNReachability()
  let reachabilityManager = Alamofire.NetworkReachabilityManager(host: "www.google.com")

  fileprivate var previousStatus: NetworkReachabilityManager.NetworkReachabilityStatus = .unknown

  func startNetworkReachabilityObserver() {
    self.reachabilityManager?.listener = { status in
      switch status {
      case .reachable(let type):
        if type == .ethernetOrWiFi {
          NSLog("Network is reachable over Wifi")
        } else {
          NSLog("Network is reachable over WWAN")
        }
        let notiName = Notification.Name(rawValue: KNReachability.kNetworkReachableNotificationKey)
        NotificationCenter.default.post(name: notiName, object: type)
        if self.previousStatus == .notReachable {
          self.showSuccessTopBannerMessage(with: "Network Restore", message: "")
        }
      case .unknown:
        NSLog("Network reachability is unknown")
        let notiName = Notification.Name(rawValue: KNReachability.kNetworkUnreachableNotificationKey)
        NotificationCenter.default.post(name: notiName, object: nil)
      case .notReachable:
        NSLog("Network is not reachable.")
        if self.previousStatus != .notReachable {
          self.showWarningTopBannerMessage(with: "Network Error", message: "No internet connection")
        }
        let notiName = Notification.Name(rawValue: KNReachability.kNetworkUnreachableNotificationKey)
        NotificationCenter.default.post(name: notiName, object: nil)
      }
      self.previousStatus = status
    }
    self.reachabilityManager?.startListening()
  }
}
