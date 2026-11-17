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
            
            self.syncViewBottom.constant = -self.view.safeAreaInsets.bottom - 15
            self.syncStack.backgroundColor = UIColor(displayP3Red: 0, green: 0, blue: 0, alpha: 0.2)
            self.view.layoutIfNeeded()
        }) { _ in
            UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
                self.syncViewBottom.constant = -self.view.safeAreaInsets.bottom
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
    
    func updateSync(action:SyncAction, type:SyncType) {
        
        switch action {
        case .complete: self.completeSync(type)
        case .start: self.startSync(type)
        }
    }
    
    private func syncIcons(_ type:SyncType) -> (spinner: UIActivityIndicatorView, checkmark: UIImageView, problem: UIImageView?) {
        switch type {
        case .conversion: return (self.spinnerConversion, self.checkmarkConversion, self.problemConversion)
        case .ldk: return (self.spinnerLDK, self.checkmarkLDK, self.problemLDK)
        case .wallet: return (self.spinnerSync, self.checkmarkSync, self.problemSync)
        case .final: return (self.spinnerFinal, self.checkmarkFinal, nil)
        }
    }
    
    func startSync(_ type:SyncType) {
        DispatchQueue.main.async {
            let icons = self.syncIcons(type)
            icons.spinner.startAnimating()
            icons.checkmark.alpha = 0
            icons.problem?.alpha = 0
        }
    }
    
    func failSync(_ type:SyncType) {
        DispatchQueue.main.async {
            let icons = self.syncIcons(type)
            icons.spinner.stopAnimating()
            icons.problem?.alpha = 1
        }
    }
    
    func completeSync(_ type:SyncType) {
        DispatchQueue.main.async {
            let icons = self.syncIcons(type)
            icons.spinner.stopAnimating()
            icons.checkmark.alpha = 1
            icons.problem?.alpha = 0
            
            if type == .final {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.hideSyncView()
                }
            }
        }
    }
    
}

enum SyncType {
    case conversion
    case ldk
    case wallet
    case final
}

enum SyncAction {
    case complete
    case start
}
