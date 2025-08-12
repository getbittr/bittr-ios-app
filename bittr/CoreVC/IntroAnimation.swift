//
//  IntroAnimation.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension CoreViewController {

    override func viewDidLayoutSubviews() {
        firstCoin.layer.cornerRadius = firstCoin.bounds.height / 2
        secondCoin.layer.cornerRadius = firstCoin.bounds.height / 2
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        // Determine whether to show pin view or signup view.
        if CacheManager.getPin() != nil {
            // Wallet exists. Launch pin.
            self.signupAlpha = 0
            self.blackSignupAlpha = 0
            // If signupAlpha is 0, the intro animation will display the PinVC upon completion. Otherwise, it will display the SignupVC.
        } else {
            // No wallet exists yet. Load SignupVC ahead of intro animation completion.
            self.launchSignup(onPage: 3)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        // Set correct height constraint for menu bar.
        if #available(iOS 13.0, *) {
            if let window = UIApplication.shared.windows.first {
                if window.safeAreaInsets.bottom == 0 {
                    self.menuBarViewHeight.constant = 68
                }
            }
        } else if #available(iOS 11.0, *) {
            if let window = UIApplication.shared.keyWindow {
                if window.safeAreaInsets.bottom == 0 {
                    self.menuBarViewHeight.constant = 68
                }
            }
        }
        
        // Start startup animation sequence.
        UIView.animate(withDuration: 0.6, delay: 0.3, options: .curveEaseInOut) {
            self.firstCoinCenterX.constant = -40
            self.firstCoinCenterY.constant = 40
            self.view.layoutIfNeeded()
        } completion: { finished in
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                self.logoViewWidth.constant = 111
                self.view.layoutIfNeeded()
            } completion: { finished in
                UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
                    self.logoViewWidth.constant = 106
                    self.view.layoutIfNeeded()
                } completion: { finished in
                    UIView.animate(withDuration: 0.3, delay: 0.3, options: .curveEaseInOut) {
                        NSLayoutConstraint.deactivate([self.logoViewCenterY])
                        self.logoViewTop = NSLayoutConstraint(item: self.logoView, attribute: .top, relatedBy: .equal, toItem: self.view.safeAreaLayoutGuide, attribute: .top, multiplier: 1, constant: 0)
                        NSLayoutConstraint.activate([self.logoViewTop])
                        self.signupContainerView.alpha = self.signupAlpha
                        if self.signupAlpha == 0 {
                            self.pinContainerView.alpha = 1
                            self.topBar.alpha = 1
                        }
                        self.view.layoutIfNeeded()
                    } completion: { finished in
                        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
                            NSLayoutConstraint.deactivate([self.logoViewTop])
                            self.logoViewTop = NSLayoutConstraint(item: self.logoView, attribute: .top, relatedBy: .equal, toItem: self.view.safeAreaLayoutGuide, attribute: .top, multiplier: 1, constant: 10)
                            NSLayoutConstraint.activate([self.logoViewTop])
                            self.finalLogo.alpha = 1
                            self.view.layoutIfNeeded()
                        } completion: { finished in
                            self.coin1.alpha = 0
                            self.coin3.alpha = 0
                            self.secondCoin.alpha = 0
                            self.blackCoin.alpha = 0
                            self.firstCoin.alpha = 0
                            self.coverView.alpha = 0
                            self.homeContainerView.alpha = 1
                            self.menuBarView.alpha = 1
                            self.blackSignupBackground.alpha = 1
                            self.changeColors()
                            
                            // Check internet connection.
                            if !Reachability.isConnectedToNetwork() {
                                // User not connected to internet.
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        }
                    }
                }
            }
        }
    }

}
