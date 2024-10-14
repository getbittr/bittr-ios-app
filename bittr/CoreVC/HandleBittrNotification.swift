//
//  HandleBittrNotification.swift
//  bittr
//
//  Created by Tom Melters on 21/03/2024.
//

import UIKit

extension CoreViewController {

    @objc func handleBittrNotification(notification:NSNotification) {
        
        // Show to the user information that was received from a Bittr push notification.
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let notificationData = userInfo["bittr_notification"] as? [String: Any] {
                
                let headerText = notificationData["header_text"] as? String ?? "oops"
                let bodyText = notificationData["body_text"] as? String ?? Language.getWord(withID: "bittrnotificationfail")
                
                let notificationDict:[String: Any] = ["question":headerText,"answer":bodyText]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
            }
        }
    }

}
