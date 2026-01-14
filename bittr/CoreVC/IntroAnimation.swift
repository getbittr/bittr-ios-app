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
    
    override func viewDidAppear(_ animated: Bool) {
        
        // Start startup animation sequence.
        // Coin slides into coin slot.
        UIView.animate(withDuration: 0.6, delay: 0.3, options: .curveEaseInOut) {
            self.firstCoinCenterX.constant = -40
            self.firstCoinCenterY.constant = 40
            self.view.layoutIfNeeded()
        } completion: { finished in
            // Logo widens to unveil bittr text.
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                self.logoViewWidth.constant = 111
                self.view.layoutIfNeeded()
            } completion: { finished in
                // Logo finishes widening with a bounce.
                UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
                    self.logoViewWidth.constant = 106
                    self.view.layoutIfNeeded()
                } completion: { finished in
                    // Logo slides from center to top.
                    UIView.animate(withDuration: 0.3, delay: 0.3, options: .curveEaseInOut) {
                        NSLayoutConstraint.deactivate([self.logoViewCenterY])
                        self.logoViewTop = NSLayoutConstraint(item: self.logoView, attribute: .top, relatedBy: .equal, toItem: self.view.safeAreaLayoutGuide, attribute: .top, multiplier: 1, constant: 0)
                        NSLayoutConstraint.activate([self.logoViewTop])
                        self.topBar.backgroundColor = Colors.getColor("transparentyellow")
                        self.coin1.alpha = 0
                        self.coin3.alpha = 0
                        self.secondCoin.alpha = 0
                        self.blackCoin.alpha = 0
                        self.firstCoin.alpha = 0
                        self.coverView.alpha = 0
                        self.finalLogo.alpha = 1
                        self.topBar.alpha = 1
                        self.upperYellowCurve.fillColor = Colors.getColor("transparentyellow")
                        self.lowerYellowCurve.fillColor = Colors.getColor("yelloworblue3")
                        if CacheManager.darkModeIsOn() {
                            self.finalLogoDarkMode.alpha = 1
                            self.bittrTextDarkMode.alpha = 1
                        }
                        self.view.layoutIfNeeded()
                        self.showPinOrSignup()
                    } completion: { finished in
                        // Logo finishes sliding with a bounce.
                        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
                            NSLayoutConstraint.deactivate([self.logoViewTop])
                            self.logoViewTop = NSLayoutConstraint(item: self.logoView, attribute: .top, relatedBy: .equal, toItem: self.view.safeAreaLayoutGuide, attribute: .top, multiplier: 1, constant: 10)
                            NSLayoutConstraint.activate([self.logoViewTop])
                            self.view.layoutIfNeeded()
                        } completion: { finished in
                            // Any final adjustments after animation.
                            self.homeContainerView.alpha = 1
                            self.menuBarContainer.alpha = 1
                            self.blackSignupBackground.alpha = 1
                            self.changeColors()
                            self.upperYellowCurve.alpha = 1
                            self.lowerYellowCurve.alpha = 1
                        }
                    }
                }
            }
        }
    }

}
