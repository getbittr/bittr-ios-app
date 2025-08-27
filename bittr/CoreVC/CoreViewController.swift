//
//  CoreViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/03/2023.
//

import UIKit
import LDKNode
import BitcoinDevKit
import LDKNodeFFI

class CoreViewController: UIViewController {

    // Environment is now automatically determined by build configuration
    // No need to manually set devEnvironment - it's handled by EnvironmentConfig
    
    // Startup animation elements
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
    
    // Top screen views
    @IBOutlet weak var finalLogo: UIImageView!
    @IBOutlet weak var coverView: UIView!
    @IBOutlet weak var topBar: UIView!
    @IBOutlet weak var yellowcurve: UIImageView!
    @IBOutlet weak var lowerTopBar: UIView!
    @IBOutlet weak var lowerYellowcurve: UIImageView!
    @IBOutlet weak var bittrText: UIImageView!
    
    // Container view and constraints for HomeVC
    @IBOutlet weak var homeContainerView: UIView!
    @IBOutlet weak var homeContainerViewLeading: NSLayoutConstraint!
    @IBOutlet weak var homeContainerViewTrailing: NSLayoutConstraint!
    
    // Menu bar elements
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
    @IBOutlet weak var leftImageUnselected: UIImageView!
    @IBOutlet weak var middleImageUnselected: UIImageView!
    @IBOutlet weak var rightImageUnselected: UIImageView!
    
    // Container views for PinVC and SignupVC
    @IBOutlet weak var pinContainerView: UIView!
    @IBOutlet weak var signupContainerView: UIView!
    @IBOutlet weak var signupBottom: NSLayoutConstraint!
    @IBOutlet weak var blackSignupBackground: UIView!
    @IBOutlet weak var blackSignupButton: UIButton!
    @IBOutlet weak var pinBottom: NSLayoutConstraint!
    var signupAlpha:CGFloat = 1
    var blackSignupAlpha:CGFloat = 0.3
    var newMnemonic:[String]?
    var resettingPin = false
    
    // Variables for notification handling
    var didBecomeVisible = false
    var needsToHandleNotification = false
    var wasNotified = false
    var lightningNotification:NSNotification?
    @IBOutlet weak var pendingView: UIView!
    @IBOutlet weak var pendingSpinner: UIActivityIndicatorView!
    @IBOutlet weak var pendingLabel: UILabel!
    var varSpecialData:[String: Any]?
    var receivedBittrTransaction:Transaction?
    var isHandlingSwapNotification = false
    
    // Connection to VCs
    var homeVC:HomeViewController?
    var infoVC:InfoViewController?
    var settingsVC:SettingsViewController?
    var signupVC:SignupViewController?
    var buyVC:BuyViewController?
    
    // Articles
    var allArticles:[String:Article]?
    var allImages:[String:Data]?
    
    // Elements for QuestionVC
    var tappedQuestion = ""
    var tappedAnswer = ""
    var tappedType:String?
    
    // Syncing status
    var didStartNode = false
    var walletHasSynced = false
    var syncStatus = "startnode"
    @IBOutlet weak var statusConversion: UILabel!
    @IBOutlet weak var statusLightning: UILabel!
    @IBOutlet weak var statusBlockchain: UILabel!
    @IBOutlet weak var statusSyncing: UILabel!
    @IBOutlet weak var statusFinal: UILabel!
    @IBOutlet weak var syncStack: UIView!
    @IBOutlet weak var syncViewBottom: NSLayoutConstraint!
    @IBOutlet weak var syncViewLowerBackground: UIView!
    @IBOutlet weak var syncCloseButton: UIButton!
    
    // Client details
    var bittrWallet = BittrWallet()
    var walletSync:BackgroundSync?
    
    // Syncing status view
    @IBOutlet weak var statusView: UIView!
    @IBOutlet weak var spinnerConversion: UIActivityIndicatorView!
    @IBOutlet weak var spinnerLDK: UIActivityIndicatorView!
    @IBOutlet weak var spinnerBDK: UIActivityIndicatorView!
    @IBOutlet weak var spinnerSyncing: UIActivityIndicatorView!
    @IBOutlet weak var spinnerFinal: UIActivityIndicatorView!
    @IBOutlet weak var checkmarkConversion: UIImageView!
    @IBOutlet weak var checkmarkLDK: UIImageView!
    @IBOutlet weak var checkmarkBDK: UIImageView!
    @IBOutlet weak var checkmarkSyncing: UIImageView!
    @IBOutlet weak var checkmarkFinal: UIImageView!
    
    // Generic spinner
    @IBOutlet weak var fullViewCover: UIView!
    @IBOutlet weak var genericSpinner: UIActivityIndicatorView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Environment is now handled by EnvironmentConfig based on build configuration
        
        // Load Bittr wallet details.
        let deviceKey = EnvironmentConfig.cacheKey(for: "device")
        if let deviceDict = UserDefaults.standard.value(forKey: deviceKey) as? NSDictionary {
            self.bittrWallet = CacheManager.parseDevice(deviceDict: deviceDict)
        }
        
        // Corner radii.
        self.selectedView.layer.cornerRadius = 13
        self.leftWhite.layer.cornerRadius = 13
        self.middleWhite.layer.cornerRadius = 13
        self.rightWhite.layer.cornerRadius = 13
        self.pendingView.layer.cornerRadius = 13
        self.statusView.layer.cornerRadius = 13
        
        // Button titles
        self.leftButton.setTitle("", for: .normal)
        self.middleButton.setTitle("", for: .normal)
        self.rightButton.setTitle("", for: .normal)
        self.syncCloseButton.setTitle("", for: .normal)
        
        // Opacities
        self.yellowcurve.alpha = 0.85
        
        // Add observers.
        NotificationCenter.default.addObserver(self, selector: #selector(handlePaymentNotification), name: NSNotification.Name(rawValue: "handlepaymentnotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBittrNotification), name: NSNotification.Name(rawValue: "handlebittrnotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSwapNotificationFromBackground), name: NSNotification.Name(rawValue: "swapNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLightningAddressNotification), name: NSNotification.Name(rawValue: "lightningAddressNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        // Set words.
        self.setWords()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if self.walletSync != nil {
            self.walletSync!.stop()
            self.walletSync = nil
        }
    }
    
    @IBAction func blackSignupButtonTapped(_ sender: UIButton) {
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
            
            self.syncViewBottom.constant = 0
            self.blackSignupBackground.alpha = 0
            self.view.layoutIfNeeded()
        }) { _ in
            self.statusView.alpha = 0
            self.blackSignupButton.alpha = 0
        }
    }
    
    @IBAction func closeSyncTapped(_ sender: UIButton) {
        self.hideSyncView()
    }
    
    @objc func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("grey3orblue1")
        self.leftWhite.backgroundColor = Colors.getColor("grey3orblue1")
        self.middleWhite.backgroundColor = Colors.getColor("grey3orblue1")
        self.rightWhite.backgroundColor = Colors.getColor("grey3orblue1")
        self.fullViewCover.backgroundColor = Colors.getColor("yelloworblue3")
        
        self.lowerTopBar.backgroundColor = Colors.getColor("yelloworblue3")
        self.topBar.backgroundColor = Colors.getColor("transparentyellow")
        
        if CacheManager.darkModeIsOn() {
            // Dark mode is on.
            self.leftImageUnselected.image = UIImage(named: "buttonpigwhite")
            self.middleImageUnselected.image = UIImage(named: "buttonmagazinewhite")
            self.rightImageUnselected.image = UIImage(named: "buttonsettingswhite")
            self.yellowcurve.image = UIImage(named: "yellowcurvedark")
            self.lowerYellowcurve.image = UIImage(named: "yellowcurvedark")
            self.bittrText.image = UIImage(named: "bittrtextwhite")
            self.finalLogo.image = UIImage(named: "logodarkmode80")
        } else {
            // Dark mode is off.
            self.leftImageUnselected.image = UIImage(named: "buttonpigblack")
            self.middleImageUnselected.image = UIImage(named: "buttonmagazineblack")
            self.rightImageUnselected.image = UIImage(named: "buttonsettingsblack")
            self.lowerYellowcurve.image = UIImage(named: "yellowcurve")
            self.yellowcurve.image = UIImage(named: "yellowcurve")
            self.bittrText.image = UIImage(named: "bittrtext")
            self.finalLogo.image = UIImage(named: "logo80")
        }
    }
    
    @objc func setWords() {
        
        self.statusConversion.text = Language.getWord(withID: "fetchconversionrates")
        self.statusLightning.text = Language.getWord(withID: "startlightningnode")
        self.statusBlockchain.text = Language.getWord(withID: "initiatewallet")
        self.statusSyncing.text = Language.getWord(withID: "syncwallet")
        self.statusFinal.text = Language.getWord(withID: "finalcalculations")
    }
    
    @objc func handleLightningAddressNotification(notification: NSNotification) {
        
        if let userInfo = notification.userInfo as? [String: Any] {
            print("Received lightning address notification: \(userInfo)")
            
            // Extract the notification data
            guard let amountMsats = userInfo["amount_msats"] as? Int,
                  let metadata = userInfo["metadata"] as? String,
                  let timeSent = userInfo["time_sent"] as? String,
                  let username = userInfo["username"] as? String,
                  let endpoint = userInfo["endpoint"] as? String else {
                print("Missing required data in lightning address notification")
                return
            }
            
            // Calculate SHA256 hash from metadata
            let descriptionHash = metadata.sha256()
            
            // Check if user is signed in
            if self.didBecomeVisible == true {
                // User is signed in, handle notification immediately
                self.handleLightningAddressNotificationImmediately(amountMsats: amountMsats, descriptionHash: descriptionHash, timeSent: timeSent, username: username, endpoint: endpoint)
            } else {
                // User hasn't signed in yet, store notification for later
                self.needsToHandleNotification = true
                self.wasNotified = true
                self.lightningNotification = notification
                
                self.showAlert(presentingController: self, title: "Payment Request", message: "Someone wants to pay you \(amountMsats/1000) satoshis! Please sign in to accept the payment.", buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        }
    }
    
    private func handleLightningAddressNotificationImmediately(amountMsats: Int, descriptionHash: String, timeSent: String, username: String, endpoint: String) {
        
        // Show loading UI
        self.pendingLabel.text = "Generating invoice..."
        self.pendingSpinner.startAnimating()
        self.pendingView.alpha = 1
        self.blackSignupBackground.alpha = 0.2
        
        Task {
            do {
                let invoice = try await LightningNodeService.shared.receivePaymentWithHash(
                    amountMsat: UInt64(amountMsats),
                    descriptionHash: descriptionHash,
                    expirySecs: 3600
                )
                
                print("Generated invoice for lightning address payment: \(invoice.description)")
                
                // Post the invoice to the specified endpoint
                let parameters: [String: Any] = [
                    "invoice": invoice.description,
                    "amount_msats": amountMsats,
                    "description_hash": descriptionHash,
                    "time_sent": timeSent,
                    "username": username
                ]
                
                await CallsManager.makeApiCall(url: endpoint, parameters: parameters, getOrPost: "POST") { result in
                    
                    DispatchQueue.main.async {
                        // Hide loading UI
                        self.pendingSpinner.stopAnimating()
                        self.pendingView.alpha = 0
                        self.blackSignupBackground.alpha = 0
                        
                        switch result {
                        case .success(let receivedDictionary):
                            print("Successfully posted invoice to endpoint: \(receivedDictionary)")
                            // No alert needed - user will receive payment notification soon
                            
                        case .failure(let error):
                            print("Failed to post invoice to endpoint: \(error)")
                            // Show error message with support contact
                            self.showAlert(presentingController: self, title: "Payment Request Failed", message: "We couldn't process this payment request. If this keeps happening, please contact support@getbittr.com", buttons: [Language.getWord(withID: "okay")], actions: nil)
                        }
                    }
                }
                
            } catch {
                print("Failed to generate invoice for lightning address payment: \(error)")
                
                DispatchQueue.main.async {
                    // Hide loading UI
                    self.pendingSpinner.stopAnimating()
                    self.pendingView.alpha = 0
                    self.blackSignupBackground.alpha = 0
                    
                    // Show error message with support contact
                    self.showAlert(presentingController: self, title: "Payment Request Failed", message: "We couldn't process this payment request. If this keeps happening, please contact support@getbittr.com", buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            }
        }
    }
    
}
