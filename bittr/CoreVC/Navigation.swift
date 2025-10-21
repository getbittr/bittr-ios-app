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
        
        let centerConstants:[CGFloat] = [-99, 0, 100]
        let centerXConstant = centerConstants[sender.tag]
        let leadingConstant = CGFloat(sender.tag * -1) * self.view.safeAreaLayoutGuide.layoutFrame.size.width
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            self.selectedViewCenterX.constant = centerXConstant
            self.homeContainerViewLeading.constant = leadingConstant
            self.homeContainerViewTrailing.constant = leadingConstant
            self.middleWhite.layer.shadowOpacity = {
                if sender.tag == 1, CacheManager.academyBetaIsOn() {
                    return 0.1
                } else {
                    return 0
                }
            }()
            self.view.layoutIfNeeded()
        } completion: { _ in
            if sender.tag != 1 {
                self.hideInfoVC()
            }
        }
    }
    
    
    func loadInfoVC() {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let vcIdentifier:String = {
            if CacheManager.academyBetaIsOn() {
                return "Academy"
            } else {
                return "Info"
            }
        }()
        let newChild = storyboard.instantiateViewController(withIdentifier: vcIdentifier)
        
        if let newChild = newChild as? InfoViewController {
            newChild.coreVC = self
            self.infoVC = newChild
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
