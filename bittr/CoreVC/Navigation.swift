//
//  Navigation.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension CoreViewController {

    @IBAction func menuButtonTapped(_ sender: UIButton) {
        
        var centerXConstant:CGFloat = 0
        let viewWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
        var leadingConstant:CGFloat = 0
        
        switch sender.accessibilityIdentifier {
        case "left":
            centerXConstant = -99;
            leadingConstant = 0
        case "middle":
            centerXConstant = 0;
            leadingConstant = -1 * viewWidth
        case "right":
            centerXConstant = 100;
            leadingConstant = -2 * viewWidth
        default:
            centerXConstant = -99;
            leadingConstant = 0
        }
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            self.selectedViewCenterX.constant = centerXConstant
            self.homeContainerViewLeading.constant = leadingConstant
            self.homeContainerViewTrailing.constant = leadingConstant
            self.view.layoutIfNeeded()
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
        } else if segue.identifier == "CoreToInfo" {
            if let infoVC = segue.destination as? InfoViewController {
                infoVC.coreVC = self
                self.infoVC = infoVC
            }
        } else if segue.identifier == "CoreToQuestion" {
            if let questionVC = segue.destination as? QuestionViewController {
                questionVC.headerText = self.tappedQuestion
                questionVC.answerText = self.tappedAnswer
                if let actualBittrChannel = self.bittrChannel {
                    questionVC.bittrChannel = actualBittrChannel
                }
                if let actualTappedType = self.tappedType {
                    questionVC.questionType = actualTappedType
                }
            }
        } else if segue.identifier == "CoreToLightning" {
            if let lightningPaymentVC = segue.destination as? LightningPaymentViewController {
                if let actualTransaction = self.receivedBittrTransaction {
                    lightningPaymentVC.receivedTransaction = actualTransaction
                    lightningPaymentVC.eurValue = self.eurValue
                    lightningPaymentVC.chfValue = self.chfValue
                }
            }
        }
    }
    
}
