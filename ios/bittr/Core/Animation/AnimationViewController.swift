//
//  AnimationViewController.swift
//  bittr
//
//  Created by Tom Melters on 3/31/26.
//

import UIKit

extension CoreViewController {
    
    var logoTopInset:CGFloat {
        return self.view.safeAreaInsets.top + 10
    }
    
    var centeredTopBarTop:CGFloat {
        return (self.view.bounds.height / 2) - self.logoTopInset - 15
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        self.topBarHeight.constant = self.view.safeAreaInsets.top + 50
        self.logoTop.constant = self.logoTopInset
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Corner radii for startup animation coins.
        self.firstCoin.layer.cornerRadius = self.firstCoin.bounds.height / 2
        self.secondCoin.layer.cornerRadius = self.firstCoin.bounds.height / 2
        
        // Place topBar in the vertical center ahead of startup animation.
        guard !self.logoHasMovedUp else { return }
        if self.topBarTop.constant != self.centeredTopBarTop {
            self.topBarTop.constant = self.centeredTopBarTop
            self.view.layoutIfNeeded()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // Start startup animation sequence.
        self.pinContainerView.alpha = 0
        
        self.coinSlidesIntoSlot()
    }
    
    func coinSlidesIntoSlot() {
        // Coin slides into coin slot.
        UIView.animate(withDuration: 0.6, delay: 0.3, options: .curveEaseInOut) {
            self.firstCoinCenterX.constant = -40
            self.firstCoinCenterY.constant = 40
            self.view.layoutIfNeeded()
        } completion: { finished in
            self.widenLogoView()
        }
    }
    
    func widenLogoView() {
        // Logo widens to unveil bittr text.
        UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0, options: .curveEaseInOut) {
            self.logoViewWidth.constant = 106
            self.view.layoutIfNeeded()
        } completion: { finished in
            self.checkWalletRemoval()
            self.logoSlidesToTop()
        }
    }
    
    func logoSlidesToTop() {
        
        UIView.animate(withDuration: 0.7, delay: 0.3, usingSpringWithDamping: 0.65, initialSpringVelocity: 0, options: .curveEaseInOut) {
            
            // Move up topBar.
            self.logoHasMovedUp = true
            self.topBarTop.constant = 0
            self.pinContainerView.alpha = 1
            
            // Hide logo elements.
            self.coin1.alpha = 0
            self.coin3.alpha = 0
            self.secondCoin.alpha = 0
            self.blackCoin.alpha = 0
            self.firstCoin.alpha = 0
            self.coverView.alpha = 0
            
            // Show final logo.
            self.finalLogo.alpha = 1
            if CacheManager.darkModeIsOn() {
                self.logoTextDarkMode.alpha = 1
                self.logoIconDarkMode.alpha = 1
            }
            self.view.layoutIfNeeded()
        } completion: { finished in
            // Final adjustments after animation.
            self.lowerTopBar.alpha = 1
            self.homeContainerView.alpha = 1
            self.menuBarContainer.alpha = 1
            self.blackSignupBackground.alpha = 1
            self.changeColors()
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecolors"), object: nil, userInfo: nil) as Notification)
        }
    }
    
}
