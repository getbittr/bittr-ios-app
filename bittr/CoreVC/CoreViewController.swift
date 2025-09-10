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
    @IBOutlet weak var pendingView: UIView!
    @IBOutlet weak var pendingSpinner: UIActivityIndicatorView!
    @IBOutlet weak var pendingLabel: UILabel!
    var userDidSignIn = false
    var needsToHandleNotification = false
    var wasNotified = false
    var lightningNotification:NSNotification?
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
        
        // Load Bittr wallet details.
        if let deviceDict = UserDefaults.standard.value(forKey: EnvironmentConfig.cacheKey(for: "device")) as? NSDictionary {
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
    
    override func viewWillAppear(_ animated: Bool) {
        if CacheManager.getPin() != nil {
            // Show PinVC.
            self.signupAlpha = 0
            self.blackSignupAlpha = 0
        } else {
            // Show SignupVC.
            self.launchSignup(onPage: 3)
        }
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
