//
//  AnimationViewController.swift
//  bittr
//
//  Created by Tom Melters on 3/31/26.
//

import UIKit

class AnimationViewController: UIViewController {
    
    // Startup animation elements
    @IBOutlet weak var logoView: UIView!
    @IBOutlet weak var bittrTextDarkMode: UIImageView!
    @IBOutlet weak var coverView: UIView!
    @IBOutlet weak var coin1: UIImageView!
    @IBOutlet weak var coin3: UIImageView!
    @IBOutlet weak var firstCoin: UIView!
    @IBOutlet weak var secondCoin: UIView!
    @IBOutlet weak var firstCoinCenterY: NSLayoutConstraint!
    @IBOutlet weak var firstCoinCenterX: NSLayoutConstraint!
    @IBOutlet weak var blackCoin: UIImageView!
    @IBOutlet weak var logoViewWidth: NSLayoutConstraint!
    @IBOutlet weak var logoViewCenterY: NSLayoutConstraint!
    @IBOutlet weak var finalLogo: UIImageView!
    @IBOutlet weak var finalLogoDarkMode: UIImageView!
    var logoViewTop = NSLayoutConstraint()
    
    // Variables
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidLayoutSubviews() {
        self.firstCoin.layer.cornerRadius = self.firstCoin.bounds.height / 2
        self.secondCoin.layer.cornerRadius = self.firstCoin.bounds.height / 2
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // Start startup animation sequence.
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
            self.coreVC?.checkWalletRemoval()
            self.logoSlidesToTop()
        }
    }
    
    func logoSlidesToTop() {
        
        let fadedBackground = self.view.backgroundColor?.withAlphaComponent(0)
        UIView.animate(withDuration: 0.3, delay: 0.3, options: .curveEaseInOut) {
            self.view.backgroundColor = fadedBackground
        }

        UIView.animate(withDuration: 0.7, delay: 0.3, usingSpringWithDamping: 0.65, initialSpringVelocity: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.logoViewCenterY])
            self.logoViewTop = NSLayoutConstraint(item: self.logoView, attribute: .top, relatedBy: .equal, toItem: self.view.safeAreaLayoutGuide, attribute: .top, multiplier: 1, constant: 10)
            NSLayoutConstraint.activate([self.logoViewTop])

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
                self.finalLogoDarkMode.alpha = 1
                self.bittrTextDarkMode.alpha = 1
            }
            self.view.layoutIfNeeded()
        } completion: { finished in
            // Final adjustments after animation.
            self.coreVC?.topBar.alpha = 1
            self.coreVC?.lowerTopBar.alpha = 1
            self.coreVC?.homeContainerView.alpha = 1
            self.coreVC?.menuBarContainer.alpha = 1
            self.coreVC?.blackSignupBackground.alpha = 1
            self.coreVC?.changeColors()
            self.coreVC?.animationContainer.alpha = 0
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecolors"), object: nil, userInfo: nil) as Notification)
        }
    }
    
}
