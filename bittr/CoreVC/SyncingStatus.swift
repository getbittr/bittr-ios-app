//
//  SyncingStatus.swift
//  bittr
//
//  Created by Tom Melters on 08/04/2024.
//

import UIKit

extension CoreViewController {

    @objc func updateSync(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            
            if let notificationAction = userInfo["action"] as? String, let notificationType = userInfo["type"] as? String {
                
                if notificationAction == "start" {
                    self.startSync(type: notificationType)
                } else {
                    self.completeSync(type: notificationType)
                }
            }
        }
    }
    
    func startSync(type:String) {
        switch type {
        case "conversion":
            self.spinnerConversion.startAnimating()
            self.checkmarkConversion.alpha = 0
        case "ldk":
            self.spinnerLDK.startAnimating()
            self.checkmarkLDK.alpha = 0
        case "bdk":
            self.spinnerBDK.startAnimating()
            self.checkmarkBDK.alpha = 0
        case "sync":
            self.spinnerSyncing.startAnimating()
            self.checkmarkSyncing.alpha = 0
        case "final":
            self.spinnerFinal.startAnimating()
            self.checkmarkFinal.alpha = 0
        default:
            print("No type received.")
        }
    }
    
    func completeSync(type:String) {
        switch type {
        case "conversion":
            self.spinnerConversion.stopAnimating()
            self.checkmarkConversion.alpha = 1
        case "ldk":
            self.spinnerLDK.stopAnimating()
            self.checkmarkLDK.alpha = 1
        case "bdk":
            self.spinnerBDK.stopAnimating()
            self.checkmarkBDK.alpha = 1
        case "sync":
            self.spinnerSyncing.stopAnimating()
            self.checkmarkSyncing.alpha = 1
        case "final":
            self.spinnerFinal.stopAnimating()
            self.checkmarkFinal.alpha = 1
        default:
            print("No type received.")
        }
    }
}
