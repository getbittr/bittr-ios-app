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
    
    @IBOutlet weak var pinContainerView: UIView!
    @IBOutlet weak var signupContainerView: UIView!
    @IBOutlet weak var signupBottom: NSLayoutConstraint!
    @IBOutlet weak var blackSignupBackground: UIView!
    @IBOutlet weak var pinBottom: NSLayoutConstraint!
    
    let keychain = KeychainSwift()
    
    var signupAlpha:CGFloat = 1
    var blackSignupAlpha:CGFloat = 0.3
    
    var didBecomeVisible = false
    var needsToHandleNotification = false
    var lightningNotification:NSNotification?
    
    @IBOutlet weak var pendingView: UIView!
    @IBOutlet weak var pendingSpinner: UIActivityIndicatorView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // FOR TESTING:
        //CacheManager.deleteClientInfo()
        //keychain.synchronizable = true
        //keychain.delete("")
        
        selectedView.layer.cornerRadius = 13
        leftWhite.layer.cornerRadius = 13
        middleWhite.layer.cornerRadius = 13
        rightWhite.layer.cornerRadius = 13
        pendingView.layer.cornerRadius = 13
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
        NotificationCenter.default.addObserver(self, selector: #selector(handlePaymentNotification), name: NSNotification.Name(rawValue: "handlepaymentnotification"), object: nil)
        
        // TODO: Hide after testing.
        //CacheManager.deleteClientInfo()
        
        keychain.synchronizable = true
        if CacheManager.getPin() != "empty" {
            // Wallet exists. Launch pin.
            signupAlpha = 0
            blackSignupAlpha = 0
        } else {
            if let storedPin = keychain.get("pin") {
                // Wallet exists. Launch pin. Migration away from Keychain.
                signupAlpha = 0
                blackSignupAlpha = 0
                CacheManager.storePin(pin: storedPin)
                keychain.delete("pin")
            } else {
                // No wallet exists yet. Go through signup.
            }
        }
    }
    
    @objc func startLightning() {
        
        // Step 3.
        
        Task {
            do {
                try await LightningNodeService.shared.start()
                print("Started node successfully.")
                DispatchQueue.main.async {
                    LightningNodeService.shared.connectToLightningPeer()
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                print("Can't start node. \(errorString.title): \(errorString.detail)")
            } catch {
                print("Can't start node. \(error.localizedDescription)")
            }
        }
    }
    
    
    func resetApp() {
    
        do {
            try LightningNodeService.shared.stop()
            
            keychain.synchronizable = true
            keychain.delete("")
            keychain.delete("pin")
            CacheManager.deleteClientInfo()
            
            do {
                try FileManager.default.removeItem(atPath: LightningStorage().getDocumentsDirectory())
            } catch {
                print(error.localizedDescription)
            }
            
            let notificationDict:[String: Any] = ["page":"restore"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
            
            self.signupContainerView.alpha = 1
            
            UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
                
                NSLayoutConstraint.deactivate([self.signupBottom])
                self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.signupBottom])
                self.blackSignupBackground.alpha = 1
                self.view.layoutIfNeeded()
            } completion: { finished in
                
                self.pinContainerView.alpha = 0
            }
        } catch let error as NodeError {
            print(error.localizedDescription)
            
            // LDKNode wasn't active yet.
            keychain.synchronizable = true
            keychain.delete("")
            keychain.delete("pin")
            CacheManager.deleteClientInfo()
            
            do {
                try FileManager.default.removeItem(atPath: LightningStorage().getDocumentsDirectory())
            } catch {
                print(error.localizedDescription)
            }
            
            let notificationDict:[String: Any] = ["page":"restore"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
            
            self.signupContainerView.alpha = 1
            
            UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
                
                NSLayoutConstraint.deactivate([self.signupBottom])
                self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.signupBottom])
                self.blackSignupBackground.alpha = 1
                self.view.layoutIfNeeded()
            } completion: { finished in
                
                self.pinContainerView.alpha = 0
            }
            
        } catch {
            print(error.localizedDescription)
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
                        self.signupContainerView.alpha = self.signupAlpha
                        if self.signupAlpha == 0 {
                            self.pinContainerView.alpha = 1
                            //self.homeContainerView.alpha = 1
                            //self.view.backgroundColor = UIColor(red: 252/255, green: 252/255, blue: 255/255, alpha: 1)
                            //self.menuBarView.alpha = 1
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
                            self.topBar.alpha = 1
                            self.view.backgroundColor = UIColor(red: 252/255, green: 252/255, blue: 255/255, alpha: 1)
                            self.homeContainerView.alpha = 1
                            self.menuBarView.alpha = 1
                            self.blackSignupBackground.alpha = 1
                            
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
            self.didBecomeVisible = true
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
            }
        }
    }
    
    func correctPin(spinner:UIActivityIndicatorView) {
        
        // Step 2.
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "fixgraph"), object: nil, userInfo: nil) as Notification)
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setclient"), object: nil, userInfo: nil) as Notification)
        
        startLightning()
        
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
            
            NSLayoutConstraint.deactivate([self.pinBottom])
            self.pinBottom = NSLayoutConstraint(item: self.pinContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.pinBottom])
            self.blackSignupBackground.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { finished in
            self.pinContainerView.alpha = 0
            spinner.stopAnimating()
            self.didBecomeVisible = true
        }
    }
    
    
    @objc func handlePaymentNotification(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            
            // Check for the special key that indicates this is a silent notification.
            if let specialData = userInfo["bittr_specific_data"] as? [String: Any] {
                print("Received special data: \(specialData)")
                
                if self.didBecomeVisible == true {
                    // User has signed in.
                    
                    self.pendingSpinner.startAnimating()
                    self.pendingView.alpha = 1
                    self.blackSignupBackground.alpha = 0.2
                    
                    self.facilitateNotificationPayout(specialData: specialData)
                    self.needsToHandleNotification = false
                } else {
                    // User hasn't signed in yet.
                    self.needsToHandleNotification = true
                    self.lightningNotification = notification
                    
                    let alert = UIAlertController(title: "Lightning payment", message: "Please sign in and wait a moment to receive your Lightning payment.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                    self.present(alert, animated: true)
                }
            } else {
                // No special key, so this is a normal notification.
                print("No special key found in notification.")
                //completionHandler(.noData)
            }
        }
    }
    
    
    func facilitateNotificationPayout(specialData:[String:Any]) {
        
        // Extract required data from specialData
        if let notificationId = specialData["notification_id"] as? String {
            let bitcoinAmountString = specialData["bitcoin_amount"] as? String ?? "0"
            let bitcoinAmount = Double(bitcoinAmountString) ?? 0.0
            let amountMsat = UInt64(bitcoinAmount * 100_000_000_000)
            
            
            
            let pubkey = LightningNodeService.shared.nodeId()

            
            // Call payoutLightning in an async context
            Task.init {
                
                let peers = try await LightningNodeService.shared.listPeers()
                if peers.count == 0 {
                    DispatchQueue.main.async {
                        self.pendingSpinner.stopAnimating()
                        self.pendingView.alpha = 0
                        self.blackSignupBackground.alpha = 0
                        let alert = UIAlertController(title: "Lightning payment", message: "Not connected to any peers. [1]", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                        self.present(alert, animated: true)
                    }
                } else if peers[0].nodeId == "026d74bf2a035b8a14ea7c59f6a0698d019720e812421ec02762fdbf064c3bc326", peers[0].isConnected == false {
                    DispatchQueue.main.async {
                        self.pendingSpinner.stopAnimating()
                        self.pendingView.alpha = 0
                        self.blackSignupBackground.alpha = 0
                        let alert = UIAlertController(title: "Lightning payment", message: "Not connected to any peers. [2]", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                        self.present(alert, animated: true)
                    }
                }
                
                let invoice = try await LightningNodeService.shared.receivePayment(
                    amountMsat: amountMsat,
                    description: notificationId,
                    expirySecs: 3600
                )
                
                let lightningSignature = try await LightningNodeService.shared.signMessage(message: notificationId)
                
                do {
                    let payoutResponse = try await BittrService.shared.payoutLightning(notificationId: notificationId, invoice: invoice, signature: lightningSignature, pubkey: pubkey)
                    print("Payout successful. PreImage: \(payoutResponse.preImage ?? "N/A")")
                    //completionHandler(.newData)
                    
                    DispatchQueue.main.async {
                        self.pendingSpinner.stopAnimating()
                        self.pendingView.alpha = 0
                        self.blackSignupBackground.alpha = 0
                        self.performSegue(withIdentifier: "CoreToLightning", sender: self)
                    }
                } catch {
                    print("Error occurred: \(error.localizedDescription)")
                    //completionHandler(.failed)
                }
            }
        } else {
            print("Required data not found in notification.")
            //completionHandler(.noData)
        }
    }
    
    
}
