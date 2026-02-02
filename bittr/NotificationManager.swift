//
//  NotificationManager.swift
//  bittr
//
//  Created by Tom Melters on 1/28/26.
//

import UserNotifications
import UIKit


// MARK: Handling
extension AppDelegate {
    func handleNotification(userInfo:[AnyHashable:Any], id:String?, title:String?, body:String?) {
        
        // Make sure the notification hasn't already been handled.
        // Check whether there's a cached notification.
        // Make sure the cached notification and the new one don't have the same ID.
        // Make sure the cached notification came in more than 10 seconds ago.
        if CacheManager.getLastNotification() == nil || ((CacheManager.getLastNotification()!.id == nil || CacheManager.getLastNotification()!.id! != id) && (CacheManager.getLastNotification()!.date == nil || Date().timeIntervalSince(CacheManager.getLastNotification()!.date!) > 10)) {
            Log.info("Will cache new notification.")
            
            let thisNotification = userInfo.toNotification()
            thisNotification.id = id
            thisNotification.title = title
            thisNotification.body = body
            CacheManager.cacheLastNotification(thisNotification)
            
            Log.info("Notification type: \(thisNotification.type)")
            
            // Handle incoming notification.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                thisNotification.handle()
            }
        } else {
            Log.info("Notification has already been cached and handled.")
        }
    }
}

extension BittrNotification {
    func handle() {
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "newNotification"), object: nil, userInfo: nil) as Notification)
    }
}

extension CoreViewController {
    @objc func newNotification() {
        
        if let thisNotification = CacheManager.getLastNotification() {
            // Notification found.
            
            switch thisNotification.type {
                
            case .lightningPayout:
                self.handlePayoutNotification(thisNotification)
            case .information:
                self.handleBittrNotification(thisNotification)
            case .swap:
                if let swapVC = self.homeVC?.moveVC?.swapVC {
                    // SwapVC is open.
                    swapVC.handleSwapNotification(thisNotification)
                } else {
                    // SwapVC is closed.
                    self.handleSwapNotificationFromBackground(thisNotification)
                }
            case .lnUrl:
                self.handleLightningAddressNotification(thisNotification)
            case .unknown:
                self.handleBittrNotification(thisNotification)
            }
            
            if thisNotification.id != nil, !thisNotification.hasBeenHandled {
                CacheManager.didHandleNotification(thisNotification.id!)
            }
        } else {
            Log.info("No notification was found in cache.")
        }
    }
}


// MARK: Object
class BittrNotification: NSObject {
    
    // General
    var id:String?
    var date:Date?
    var type:BittrNotificationType = .unknown
    var title:String?
    var body:String?
    var hasBeenHandled = false
    
    // Lightning payout
    var notificationID:String?
    var amountMsat:Int? // lightningPayout and lnUrl item.
    
    // Information
    var headerText:String?
    var bodyText:String?
    
    // Swap
    var swapID:String?
    var status:String?
    
    // LNURL
    var metadata:String?
    var timeSent:String?
    var username:String?
    var endpoint:String?
}

enum BittrNotificationType {
    case lightningPayout
    case information
    case swap
    case lnUrl
    case unknown
}


// MARK: Caching
extension CacheManager {
    
    static func cacheLastNotification(_ bittrNotification: BittrNotification) {
        
        let notificationDict = bittrNotification.toDictionary()
        UserDefaults.standard.set(notificationDict, forKey: "latestNotification")
    }
    
    static func getLastNotification() -> BittrNotification? {
        
        if let notificationDict = UserDefaults.standard.value(forKey: "latestNotification") as? NSDictionary {
            let thisNotification = notificationDict.toNotification()
            return thisNotification
        } else {
            return nil
        }
    }
    
    static func didHandleNotification(_ id:String) {
        if let lastNotification = self.getLastNotification(), lastNotification.id == id {
            lastNotification.hasBeenHandled = true
            self.cacheLastNotification(lastNotification)
        }
    }
}


// MARK: Receiving
extension AppDelegate {
    
    // Notification came in while the app was closed.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Log.info("Did receive notification while app was closed.")
        
        let request = response.notification.request
        self.handleNotification(userInfo: request.content.userInfo, id: request.identifier, title: request.content.title, body: request.content.body)
    }
    
    // Notification comes in while the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Log.info("Did receive notification while app was open.")
        
        let request = notification.request
        self.handleNotification(userInfo: request.content.userInfo, id: request.identifier, title: request.content.title, body: request.content.body)
        
        completionHandler([.banner, .list])
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Log.info("Did receive notification while app was closed. 2")
        
        self.handleNotification(userInfo: userInfo, id: UUID().uuidString, title: nil, body: nil)
        
        completionHandler(.newData)
    }
}


// MARK: Parsing
extension BittrNotification {
    func toDictionary() -> NSDictionary {
        
        let thisDictionary = NSMutableDictionary()
        
        if self.id != nil {
            thisDictionary.setValue(self.id!, forKey: "id")
        }
        
        if self.date != nil {
            thisDictionary.setValue(Int(self.date!.timeIntervalSince1970), forKey: "date")
        }
        
        if self.title != nil {
            thisDictionary.setValue(self.title!, forKey: "title")
        }
        
        if self.body != nil {
            thisDictionary.setValue(self.body!, forKey: "body")
        }
        
        thisDictionary.setValue(self.hasBeenHandled, forKey: "hasBeenHandled")
        
        switch self.type {
        case .lightningPayout:
            thisDictionary.setValue("lightningPayout", forKey: "type")
            if self.notificationID != nil {
                thisDictionary.setValue(self.notificationID!, forKey: "notificationID")
            }
            if self.amountMsat != nil {
                thisDictionary.setValue(self.amountMsat!, forKey: "amountMsat")
            }
        case .information:
            thisDictionary.setValue("information", forKey: "type")
            if self.headerText != nil {
                thisDictionary.setValue(self.headerText!, forKey: "headerText")
            }
            if self.bodyText != nil {
                thisDictionary.setValue(self.bodyText!, forKey: "bodyText")
            }
        case .swap:
            thisDictionary.setValue("swap", forKey: "type")
            if self.swapID != nil {
                thisDictionary.setValue(self.swapID!, forKey: "swapID")
            }
            if self.status != nil {
                thisDictionary.setValue(self.status!, forKey: "status")
            }
        case .lnUrl:
            thisDictionary.setValue("lnUrl", forKey: "type")
            if self.amountMsat != nil {
                thisDictionary.setValue(self.amountMsat!, forKey: "amountMsat")
            }
            if self.metadata != nil {
                thisDictionary.setValue(self.metadata!, forKey: "metadata")
            }
            if self.timeSent != nil {
                thisDictionary.setValue(self.timeSent!, forKey: "timeSent")
            }
            if self.username != nil {
                thisDictionary.setValue(self.username!, forKey: "username")
            }
            if self.endpoint != nil {
                thisDictionary.setValue(self.endpoint!, forKey: "endpoint")
            }
        case .unknown:
            thisDictionary.setValue("unknown", forKey: "type")
        }
        
        return thisDictionary
    }
}

extension [AnyHashable:Any] {
    func toNotification() -> BittrNotification {
        
        let thisNotification = BittrNotification()
        thisNotification.date = Date()
        
        if let notificationData = self["bittr_specific_data"] as? [String: Any] {
            
            // Bittr Lightning payout.
            thisNotification.type = .lightningPayout
            
            // Get notification ID.
            if let notificationID = notificationData["notification_id"] as? String {
                thisNotification.notificationID = notificationID
            }
            
            // Get bitcoin amount.
            if let bitcoinAmountString = notificationData["bitcoin_amount"] as? String {
                thisNotification.amountMsat = bitcoinAmountString.toNumber().inSatoshis() * 1000
            }
            
        } else if let notificationData = self["bittr_notification"] as? [String: Any] {
            
            // General Bittr information.
            thisNotification.type = .information
            
            // Get header text.
            thisNotification.headerText = notificationData["header_text"] as? String ?? "oops"
            
            // Get body text.
            thisNotification.bodyText = notificationData["body_text"] as? String ?? Language.getWord(withID: "bittrnotificationfail")
            
        } else if let notificationData = self["swap_notification"] as? [String: Any] {
            
            // Swap notification.
            thisNotification.type = .swap
            
            // Get Swap ID.
            if let swapID = notificationData["swap_id"] as? String {
                thisNotification.swapID = swapID
            }
            
            if let status = notificationData["status"] as? String {
                thisNotification.status = status
            }
            
        } else if let notificationData = self["lightning_address_notification"] as? [String: Any] {
            
            // LNURL request.
            thisNotification.type = .lnUrl
            
            // Get amount Msat.
            if let amountMsat = notificationData["amount_msats"] as? Int {
                thisNotification.amountMsat = amountMsat
            }
            
            if let metadata = notificationData["metadata"] as? String {
                thisNotification.metadata = metadata
            }
            
            if let timeSent = notificationData["time_sent"] as? String {
                thisNotification.timeSent = timeSent
            }
            
            if let username = notificationData["username"] as? String {
                thisNotification.username = username
            }
            
            if let endpoint = notificationData["endpoint"] as? String {
                thisNotification.endpoint = endpoint
            }
            
        } else {
            
            // Unknown notification type.
            thisNotification.type = .unknown
            
        }
        
        return thisNotification
    }
}

extension NSDictionary {
    func toNotification() -> BittrNotification {
        
        let thisNotification = BittrNotification()
        
        if let id = self["id"] as? String {
            thisNotification.id = id
        }
        
        if let date = self["date"] as? Int {
            thisNotification.date = Date(timeIntervalSince1970: Double(date))
        }
        
        if let title = self["title"] as? String {
            thisNotification.title = title
        }
        
        if let body = self["body"] as? String {
            thisNotification.body = body
        }
        
        if let hasBeenHandled = self["hasBeenHandled"] as? Bool {
            thisNotification.hasBeenHandled = hasBeenHandled
        }
        
        if let type = self["type"] as? String {
            switch type {
            case "lightningPayout": thisNotification.type = .lightningPayout
            case "information": thisNotification.type = .information
            case "swap": thisNotification.type = .swap
            case "lnUrl": thisNotification.type = .lnUrl
            default: thisNotification.type = .unknown
            }
        } else {
            thisNotification.type = .unknown
        }
        
        switch thisNotification.type {
        case .lightningPayout:
            if let notificationID = self["notificationID"] as? String {
                thisNotification.notificationID = notificationID
            }
            if let amountMsat = self["amountMsat"] as? Int {
                thisNotification.amountMsat = amountMsat
            }
        case .information:
            if let headerText = self["headerText"] as? String {
                thisNotification.headerText = headerText
            }
            if let bodyText = self["bodyText"] as? String {
                thisNotification.bodyText = bodyText
            }
        case .swap:
            if let swapID = self["swapID"] as? String {
                thisNotification.swapID = swapID
            }
            if let status = self["status"] as? String {
                thisNotification.status = status
            }
        case .lnUrl:
            if let amountMsat = self["amountMsat"] as? Int {
                thisNotification.amountMsat = amountMsat
            }
            if let metadata = self["metadata"] as? String {
                thisNotification.metadata = metadata
            }
            if let timeSent = self["timeSent"] as? String {
                thisNotification.timeSent = timeSent
            }
            if let username = self["username"] as? String {
                thisNotification.username = username
            }
            if let endpoint = self["endpoint"] as? String {
                thisNotification.endpoint = endpoint
            }
        case .unknown:
            break
        }
        
        return thisNotification
    }
}
