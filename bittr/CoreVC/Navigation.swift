//
//  Navigation.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension CoreViewController {

    @IBAction func menuButtonTapped(_ sender: UIButton) {
        
        if sender.tag == 1 {
            self.loadInfoVC()
        }
        
        let menuViews:[UIView] = [self.walletView, self.academyView, self.settingsView]
        let menuConstraint = menuViews[sender.tag]
        let leadingConstant = CGFloat(sender.tag * -1) * self.view.safeAreaLayoutGuide.layoutFrame.size.width
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            // Selected menu item.
            NSLayoutConstraint.deactivate([self.selectedViewLeading, self.selectedViewTrailing])
            self.selectedViewLeading = NSLayoutConstraint(item: self.selectedView, attribute: .leading, relatedBy: .equal, toItem: menuConstraint, attribute: .leading, multiplier: 1, constant: 0)
            self.selectedViewTrailing = NSLayoutConstraint(item: self.selectedView, attribute: .trailing, relatedBy: .equal, toItem: menuConstraint, attribute: .trailing, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.selectedViewLeading, self.selectedViewTrailing])
            
            // Container view.
            self.homeContainerViewLeading.constant = leadingConstant
            self.homeContainerViewTrailing.constant = leadingConstant
            
            self.view.layoutIfNeeded()
        } completion: { _ in
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setupblur"), object: nil, userInfo: nil) as Notification)
            if sender.tag != 1 {
                self.hideInfoVC()
            }
        }
    }
    
    
    func loadInfoVC() {
        
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let newChild = storyboard.instantiateViewController(withIdentifier: "Academy")
        if let newChild = newChild as? AcademyViewController {
            newChild.coreVC = self
        }
        
        self.addChild(newChild)
        newChild.view.frame.size = self.infoContainerView.frame.size
        self.infoContainerView.addSubview(newChild.view)
        newChild.didMove(toParent: self)
    }
    
    func hideInfoVC() {
        if self.infoContainerView.subviews.count > 0 {
            for eachSubview in self.infoContainerView.subviews {
                eachSubview.removeFromSuperview()
            }
        }
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "CoreToSettings" {
            if let settingsVC = segue.destination as? SettingsViewController {
                settingsVC.coreVC = self
                self.settingsVC = settingsVC
            }
        } else if segue.identifier == "CoreToPin" {
            if let pinVC = segue.destination as? PinViewController {
                pinVC.coreVC = self
            }
        } else if segue.identifier == "CoreToHome" {
            if let homeVC = segue.destination as? HomeViewController {
                homeVC.coreVC = self
                self.homeVC = homeVC
            }
        } else if segue.identifier == "CoreToQuestion" {
            if let questionVC = segue.destination as? QuestionViewController {
                questionVC.headerText = self.tappedQuestion
                questionVC.answerText = self.tappedAnswer
                questionVC.coreVC = self
                questionVC.questionType = self.tappedType
            }
        } else if segue.identifier == "CoreToLightning" {
            if let lightningPaymentVC = segue.destination as? LightningPaymentViewController {
                if let actualTransaction = self.receivedBittrTransaction {
                    lightningPaymentVC.receivedTransaction = actualTransaction
                    lightningPaymentVC.coreVC = self
                }
            }
        }
    }
    
}
