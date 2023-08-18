//
//  CoreViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/03/2023.
//

import UIKit
import LDKNode
import KeychainSwift
import BitcoinDevKit

class CoreViewController: UIViewController {

    @IBOutlet weak var coin1: UIImageView!
    @IBOutlet weak var coin3: UIImageView!
    @IBOutlet weak var firstCoin: UIView!
    @IBOutlet weak var secondCoin: UIView!
    @IBOutlet weak var firstCoinCenterY: NSLayoutConstraint!
    @IBOutlet weak var firstCoinCenterX: NSLayoutConstraint!
    @IBOutlet weak var blackCoin: UIImageView!
    @IBOutlet weak var logoViewWidth: NSLayoutConstraint!
    @IBOutlet weak var logoViewCenterY: NSLayoutConstraint!
    @IBOutlet weak var logoView: UIView!
    var logoViewTop = NSLayoutConstraint()
    @IBOutlet weak var finalLogo: UIImageView!
    @IBOutlet weak var coverView: UIView!
    @IBOutlet weak var topBar: UIView!
    @IBOutlet weak var yellowcurve: UIImageView!
    
    @IBOutlet weak var homeContainerView: UIView!
    @IBOutlet weak var homeContainerViewLeading: NSLayoutConstraint!
    @IBOutlet weak var homeContainerViewTrailing: NSLayoutConstraint!
    
    @IBOutlet weak var menuBarView: UIView!
    @IBOutlet weak var selectedView: UIView!
    @IBOutlet weak var leftButton: UIButton!
    @IBOutlet weak var middleButton: UIButton!
    @IBOutlet weak var rightButton: UIButton!
    @IBOutlet weak var selectedViewCenterX: NSLayoutConstraint!
    @IBOutlet weak var menuBarViewHeight: NSLayoutConstraint!
    
    @IBOutlet weak var leftWhite: UIView!
    @IBOutlet weak var middleWhite: UIView!
    @IBOutlet weak var rightWhite: UIView!
    
    @IBOutlet weak var signupContainerView: UIView!
    @IBOutlet weak var signupBottom: NSLayoutConstraint!
    @IBOutlet weak var blackSignupBackground: UIView!
    
    let keychain = KeychainSwift()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // FOR TESTING:
        CacheManager.deleteClientInfo()
        //keychain.synchronizable = true
        //keychain.delete("")
        
        selectedView.layer.cornerRadius = 13
        leftWhite.layer.cornerRadius = 13
        middleWhite.layer.cornerRadius = 13
        rightWhite.layer.cornerRadius = 13
        leftButton.setTitle("", for: .normal)
        middleButton.setTitle("", for: .normal)
        rightButton.setTitle("", for: .normal)
        yellowcurve.alpha = 0.85
        
        //let blurEffectView = BlurEffectViewLight()
        //topBar.insertSubview(blurEffectView, at: 0)
        //let blurEffectView2 = BlurEffectViewLight()
        //menuBarView.insertSubview(blurEffectView2, at: 0)
        
        NotificationCenter.default.addObserver(self, selector: #selector(hideSignup), name: NSNotification.Name(rawValue: "restorewallet"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(startLightning), name: NSNotification.Name(rawValue: "startlightning"), object: nil)
        
        //startLightning()
    }
    
    @objc func startLightning() {
        
        keychain.synchronizable = true
        if let storedMnemonic = keychain.get("") {
            // Wallet already exists.
            
            Task {
                do {
                    try await LightningNodeService.shared.start()
                } catch let error as NodeError {
                    print(error.localizedDescription)
                } catch {
                    print(error.localizedDescription)
                }
            }
        } else {
            // No wallet exists yet.
            
            Task {
                do {
                    try await LightningNodeService.shared.start()
                } catch let error as NodeError {
                    print(error.localizedDescription)
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        
        firstCoin.layer.cornerRadius = firstCoin.bounds.height / 2
        secondCoin.layer.cornerRadius = firstCoin.bounds.height / 2
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setupblur"), object: nil, userInfo: nil) as Notification)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
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
        
        UIView.animate(withDuration: 0.6, delay: 0.3, options: .curveEaseInOut) {
            self.firstCoinCenterX.constant = -40
            self.firstCoinCenterY.constant = 40
            self.view.layoutIfNeeded()
        } completion: { finished in
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                self.logoViewWidth.constant = 99
                self.view.layoutIfNeeded()
            } completion: { finished in
                UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
                    self.logoViewWidth.constant = 94
                    self.view.layoutIfNeeded()
                } completion: { finished in
                    UIView.animate(withDuration: 0.3, delay: 0.3, options: .curveEaseInOut) {
                        NSLayoutConstraint.deactivate([self.logoViewCenterY])
                        self.logoViewTop = NSLayoutConstraint(item: self.logoView, attribute: .top, relatedBy: .equal, toItem: self.view.safeAreaLayoutGuide, attribute: .top, multiplier: 1, constant: 0)
                        NSLayoutConstraint.activate([self.logoViewTop])
                        self.signupContainerView.alpha = 1
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
                            self.topBar.alpha = 1
                            self.view.backgroundColor = UIColor(red: 252/255, green: 252/255, blue: 255/255, alpha: 1)
                            self.homeContainerView.alpha = 1
                            self.menuBarView.alpha = 1
                            self.blackSignupBackground.alpha = 0.3
                            
                            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setupblur"), object: nil, userInfo: nil) as Notification)
                        }
                    }
                }
            }
        }
        
        
    }
    
    
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
    

    @objc func hideSignup() {
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "fixgraph"), object: nil, userInfo: nil) as Notification)
        
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
            
            NSLayoutConstraint.deactivate([self.signupBottom])
            self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.signupBottom])
            self.blackSignupBackground.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { finished in
            self.signupContainerView.alpha = 0
        }
    }
    
}
