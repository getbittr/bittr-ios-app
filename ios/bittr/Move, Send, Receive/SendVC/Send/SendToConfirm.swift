//
//  SendToConfirm.swift
//  bittr
//
//  Created by Tom Melters on 8/24/26.
//

import UIKit

extension SendViewController {
    
    func slideFromConfirmToSend() {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                NSLayoutConstraint.deactivate([self.scrollViewTrailing])
                self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.scrollViewTrailing])
                self.view.layoutIfNeeded()
            } completion: { _ in
                self.removeConfirmView()
            }
        }
    }
    
    func slideFromSendToConfirm() {
        DispatchQueue.main.async {
            self.loadConfirmView()
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                NSLayoutConstraint.deactivate([self.scrollViewTrailing])
                self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.scrollViewTrailing])
                self.view.layoutIfNeeded()
            }
        }
    }
    
    func loadConfirmView() {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let newChild = storyboard.instantiateViewController(withIdentifier: "ConfirmSend")
        (newChild as? ConfirmSendViewController)?.coreVC = self.coreVC
        (newChild as? ConfirmSendViewController)?.sendVC = self
        self.confirmSendVC = newChild as? ConfirmSendViewController
        
        self.addChild(newChild)
        newChild.view.frame.size = self.confirmContainer.frame.size
        self.confirmContainer.addSubview(newChild.view)
        newChild.didMove(toParent: self)
    }
    
    func removeConfirmView() {
        for eachSubview in self.confirmContainer.subviews {
            eachSubview.removeFromSuperview()
        }
    }
}
