//
//  HandleBittrNotification.swift
//  bittr
//
//  Created by Tom Melters on 21/03/2024.
//

import UIKit

extension CoreViewController {

    @objc func handleBittrNotification(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let notificationData = userInfo["bittr_notification"] as? [String: Any] {
                
                let headerText = notificationData["header_text"] as? String ?? "oops"
                let bodyText = notificationData["body_text"] as? String ?? "Something went wrong processing the notification we sent to you. Please reach out if you have any questions."
                
                let notificationDict:[String: Any] = ["question":headerText,"answer":bodyText]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
            }
        }
    }

}
