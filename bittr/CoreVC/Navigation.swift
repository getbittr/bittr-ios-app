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
            let settingsVC = segue.destination as? SettingsViewController
            if let actualSettingsVC = settingsVC {
                actualSettingsVC.coreVC = self
            }
        } else if segue.identifier == "CoreToPin" {
            let pinVC = segue.destination as? PinViewController
            if let actualPinVC = pinVC {
                actualPinVC.coreVC = self
            }
        } else if segue.identifier == "CoreToHome" {
            let homeVC = segue.destination as? HomeViewController
            if let actualHomeVC = homeVC {
                actualHomeVC.coreVC = self
                self.homeVC = actualHomeVC
            }
        } else if segue.identifier == "CoreToInfo" {
            let infoVC = segue.destination as? InfoViewController
            if let actualInfoVC = infoVC {
                actualInfoVC.coreVC = self
            }
        } else if segue.identifier == "CoreToQuestion" {
            let questionVC = segue.destination as? QuestionViewController
            if let actualQuestionVC = questionVC {
                actualQuestionVC.headerText = self.tappedQuestion
                actualQuestionVC.answerText = self.tappedAnswer
                if let actualBittrChannel = self.bittrChannel {
                    actualQuestionVC.bittrChannel = actualBittrChannel
                }
                if let actualTappedType = self.tappedType {
                    actualQuestionVC.questionType = actualTappedType
                }
            }
        } else if segue.identifier == "CoreToLightning" {
            let lightningPaymentVC = segue.destination as? LightningPaymentViewController
            if let actualPaymentVC = lightningPaymentVC {
                if let actualTransaction = self.receivedBittrTransaction {
                    actualPaymentVC.receivedTransaction = actualTransaction
                    actualPaymentVC.eurValue = self.eurValue
                    actualPaymentVC.chfValue = self.chfValue
                }
            }
        } else if segue.identifier == "CoreToSignup" {
            let signupVC = segue.destination as? SignupViewController
            if let actualSignupVC = signupVC {
                actualSignupVC.coreVC = self
            }
        }
    }
    
}
