//
//  SyncingStatus.swift
//  bittr
//
//  Created by Tom Melters on 08/04/2024.
//

import UIKit

extension CoreViewController {

    func showSyncView() {
        
        self.syncViewBottom.constant = self.statusView.frame.height + self.view.safeAreaInsets.bottom
        self.view.layoutIfNeeded()
        
        self.syncStack.alpha = 1
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
            
            self.syncViewBottom.constant = -10
            self.syncStack.backgroundColor = UIColor(displayP3Red: 0, green: 0, blue: 0, alpha: 0.2)
            self.view.layoutIfNeeded()
        }) { _ in
            UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
                self.syncViewBottom.constant = 0
                self.view.layoutIfNeeded()
            }
        }
    }
    
    func hideSyncView() {
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
            
            self.syncViewBottom.constant = self.statusView.frame.height + self.view.safeAreaInsets.bottom
            self.syncStack.backgroundColor = UIColor.clear
            self.view.layoutIfNeeded()
        }) { _ in
            self.syncStack.alpha = 0
        }
    }
    
    func updateSync(action:String, type:SyncType) {
        
        if action == "start" {
            self.startSync(type: type)
        } else {
            self.completeSync(type: type)
        }
    }
    
    func startSync(type:SyncType) {
        switch type {
        case .conversion:
            self.spinnerConversion.startAnimating()
            self.checkmarkConversion.alpha = 0
        case .ldk:
            self.spinnerLDK.startAnimating()
            self.checkmarkLDK.alpha = 0
        case .bdk:
            self.spinnerBDK.startAnimating()
            self.checkmarkBDK.alpha = 0
        case .sync:
            self.spinnerSyncing.startAnimating()
            self.checkmarkSyncing.alpha = 0
        case .final:
            self.spinnerFinal.startAnimating()
            self.checkmarkFinal.alpha = 0
        }
    }
    
    func completeSync(type:SyncType) {
        switch type {
        case .conversion:
            self.spinnerConversion.stopAnimating()
            self.checkmarkConversion.alpha = 1
        case .ldk:
            self.spinnerLDK.stopAnimating()
            self.checkmarkLDK.alpha = 1
        case .bdk:
            self.spinnerBDK.stopAnimating()
            self.checkmarkBDK.alpha = 1
        case .sync:
            self.spinnerSyncing.stopAnimating()
            self.checkmarkSyncing.alpha = 1
        case .final:
            self.spinnerFinal.stopAnimating()
            self.checkmarkFinal.alpha = 1
        }
    }
}

enum SyncType {
    case conversion
    case ldk
    case bdk
    case sync
    case final
}
