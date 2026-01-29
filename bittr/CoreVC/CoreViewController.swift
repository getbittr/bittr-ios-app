//
//  CoreViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/03/2023.
//

import UIKit
import LDKNode

class CoreViewController: UIViewController {
    
    // App start booleans
    var walletIsAvailable = false
    var userHasSignedIn = false
    var walletHasSynced = false
    
    // Client details
    var bittrWallet = BittrWallet()
    var walletSync:BackgroundSync?
    
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
    @IBOutlet weak var finalLogoDarkMode: UIImageView!
    @IBOutlet weak var coverView: UIView!
    @IBOutlet weak var topBar: UIView!
    @IBOutlet weak var lowerTopBar: UIView!
    @IBOutlet weak var bittrText: UIImageView!
    @IBOutlet weak var bittrTextDarkMode: UIImageView!
    @IBOutlet weak var upperYellowCurve: BottomCurveView!
    @IBOutlet weak var lowerYellowCurve: BottomCurveView!
    
    // Container view and constraints for HomeVC
    @IBOutlet weak var homeContainerView: UIView!
    @IBOutlet weak var homeContainerViewLeading: NSLayoutConstraint!
    @IBOutlet weak var homeContainerViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var infoContainerView: UIView!
    
    // Menu bar elements
    @IBOutlet weak var menuBarContainer: UIView!
    @IBOutlet weak var selectedView: UIView!
    @IBOutlet weak var selectedViewLeading: NSLayoutConstraint!
    @IBOutlet weak var selectedViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var leftButton: UIButton!
    @IBOutlet weak var middleButton: UIButton!
    @IBOutlet weak var rightButton: UIButton!
    @IBOutlet weak var leftImageUnselected: UIImageView!
    @IBOutlet weak var middleImageUnselected: UIImageView!
    @IBOutlet weak var rightImageUnselected: UIImageView!
    @IBOutlet weak var settingsView: UIView!
    @IBOutlet weak var academyView: UIView!
    @IBOutlet weak var walletView: UIView!
    @IBOutlet weak var walletLabel: UILabel!
    @IBOutlet weak var academyLabel: UILabel!
    
    // Container views for PinVC and SignupVC
    @IBOutlet weak var pinContainerView: UIView!
    @IBOutlet weak var signupContainerView: UIView!
    @IBOutlet weak var signupBottom: NSLayoutConstraint!
    @IBOutlet weak var blackSignupBackground: UIView!
    @IBOutlet weak var blackSignupButton: UIButton!
    @IBOutlet weak var pinBottom: NSLayoutConstraint!
    var resettingPin = false
    
    // Variables for notification handling
    @IBOutlet weak var pendingView: UIView!
    @IBOutlet weak var pendingSpinner: UIActivityIndicatorView!
    @IBOutlet weak var pendingLabel: UILabel!
    var wasNotified = false
    var lightningNotification:BittrNotification?
    var receivedBittrTransaction:Transaction?
    var pendingNotificationId:String?
    var pendingSuggestedSwapAmount:Int = 0
    
    // Connection to VCs
    var homeVC:HomeViewController?
    var settingsVC:SettingsViewController?
    var signupVC:SignupViewController?
    var buyVC:BuyViewController?
    
    // Articles
    var allArticles:[String:Article]?
    var allImages:[String:Data]?
    var tappedArticle:String?
    
    // Academy
    var downloadedAcademy:[Level]?
    
    // Elements for QuestionVC
    var tappedQuestion = ""
    var tappedAnswer = ""
    var tappedType:String?
    
    // Syncing status
    @IBOutlet weak var statusConversion: UILabel!
    @IBOutlet weak var statusLightning: UILabel!
    @IBOutlet weak var statusBlockchain: UILabel!
    @IBOutlet weak var statusSyncing: UILabel!
    @IBOutlet weak var statusFinal: UILabel!
    @IBOutlet weak var syncStack: UIView!
    @IBOutlet weak var syncViewBottom: NSLayoutConstraint!
    @IBOutlet weak var syncCloseButton: UIButton!
    
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
        
        // Load Bittr wallet details.
        if let deviceDict = UserDefaults.standard.value(forKey: EnvironmentConfig.cacheKey(for: "device")) as? NSDictionary {
            self.bittrWallet = CacheManager.parseDevice(deviceDict: deviceDict)
        }
        
        // Identify current dark mode.
        CacheManager.setCurrentDarkMode(darkModeIsOn: self.darkModeIsOn())
        
        // Corner radii.
        self.selectedView.layer.cornerRadius = 8
        self.pendingView.layer.cornerRadius = 13
        self.statusView.layer.cornerRadius = 13
        self.settingsView.layer.cornerRadius = 8
        self.academyView.layer.cornerRadius = 8
        self.walletView.layer.cornerRadius = 8
        self.walletView.setShadow()
        self.academyView.setShadow()
        self.settingsView.setShadow()
        
        // Button titles
        self.leftButton.setTitle("", for: .normal)
        self.middleButton.setTitle("", for: .normal)
        self.rightButton.setTitle("", for: .normal)
        self.syncCloseButton.setTitle("", for: .normal)
        
        // Set curve color to yellow for app launch.
        self.upperYellowCurve.fillColor = UIColor(displayP3Red: 246/255, green: 199/255, blue: 68/255, alpha: 0.85)
        self.lowerYellowCurve.fillColor = UIColor(displayP3Red: 246/255, green: 199/255, blue: 68/255, alpha: 1)
        
        // Add observers.
        NotificationCenter.default.addObserver(self, selector: #selector(newNotification), name: NSNotification.Name(rawValue: "newNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBitcoinURI), name: NSNotification.Name(rawValue: "handleBitcoinURI"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLightningURI), name: NSNotification.Name(rawValue: "handleLightningURI"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        // Set words.
        self.setWords()
        
        // Check wallet.
        self.checkWalletAvailability()
    }
    
    func checkWalletAvailability() {
        
        // Check wallet availability.
        if CacheManager.getMnemonic() != nil, CacheManager.getPin() != nil {
            // Wallet has been created.
            self.walletIsAvailable = true
        } else {
            // User has not completed signup.
            self.walletIsAvailable = false
            // Remove cached mnemonic.
            CacheManager.removeMnemonic()
            // Show SignupVC.
            self.launchSignup(onPage: 3)
        }
        
        // Check for pending notifications as a fallback
        self.checkForPendingNotifications()
    }
    
    func showPinOrSignup() {
        
        // Show Pin or Signup view upon app launch.
        if self.walletIsAvailable {
            self.signupContainerView.alpha = 0
            self.pinContainerView.alpha = 1
        } else {
            self.signupContainerView.alpha = 1
            self.pinContainerView.alpha = 0
        }
    }
    
    private func checkForPendingNotifications() {
        // Check if we have a pending payment notification as a fallback
        
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
    
}
