//
//  CoreViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/03/2023.
//

import UIKit
import LDKNode
import Sentry

class CoreViewController: UIViewController {
    
    // App start booleans
    var walletIsAvailable = false
    var userHasSignedIn = false
    var walletHasSynced = false
    
    // Pin reset
    var resettingPin = false
    var removingWalletForIncorrectPin = false
    
    // Client details
    var bittrWallet = BittrWallet()
    var walletSync:BackgroundSync?
    
    // Pending notifications
    var wasNotified = false
    var lightningNotification:BittrNotification?
    var receivedBittrTransaction:Transaction?
    var pendingNotificationId:String?
    var pendingSuggestedSwapAmount:Int = 0
    var pendingPayout:BittrPendingPayout?
    
    // Pending variables
    var isFromLightningPayment = false
    var pendingLightningInvoice = ""
    
    // Other VCs
    var homeVC:HomeViewController?
    var settingsVC:SettingsViewController?
    var signupVC:SignupViewController?
    var buyVC:BuyViewController?
    var swapVC:SwapViewController?
    var receiveVC:ReceiveViewController?
    
    // Articles and Academy
    var allArticles:[String:Article]?
    var tappedArticle:String?
    var downloadedAcademy:[Level]?
    
    // QuestionVC
    var tappedQuestion = ""
    var tappedAnswer = ""
    var tappedType:String?
    
    // Top bar
    @IBOutlet weak var animationContainer: UIView!
    @IBOutlet weak var finalLogoDarkMode: UIImageView!
    @IBOutlet weak var topBar: UIView!
    @IBOutlet weak var lowerTopBar: UIView!
    @IBOutlet weak var bittrTextDarkMode: UIImageView!
    @IBOutlet weak var upperYellowCurve: BottomCurveView!
    @IBOutlet weak var lowerYellowCurve: BottomCurveView!
    
    // Year view
    @IBOutlet weak var yearView: UIView!
    @IBOutlet weak var yearLabel: UILabel!
    
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
    @IBOutlet weak var pinBottom: NSLayoutConstraint!
    
    // Variables for notification handling
    @IBOutlet weak var pendingView: UIView!
    @IBOutlet weak var pendingSpinner: UIActivityIndicatorView!
    @IBOutlet weak var pendingLabel: UILabel!
    
    // Syncing status
    @IBOutlet weak var statusConversion: UILabel!
    @IBOutlet weak var statusLightning: UILabel!
    @IBOutlet weak var statusFinal: UILabel!
    @IBOutlet weak var syncStack: UIView!
    @IBOutlet weak var syncViewBottom: NSLayoutConstraint!
    @IBOutlet weak var syncCloseButton: UIButton!
    
    // Syncing status view
    @IBOutlet weak var statusView: UIView!
    @IBOutlet weak var spinnerConversion: UIActivityIndicatorView!
    @IBOutlet weak var spinnerLDK: UIActivityIndicatorView!
    @IBOutlet weak var spinnerFinal: UIActivityIndicatorView!
    @IBOutlet weak var checkmarkConversion: UIImageView!
    @IBOutlet weak var checkmarkLDK: UIImageView!
    @IBOutlet weak var checkmarkFinal: UIImageView!
    
    // Generic spinner
    @IBOutlet weak var fullViewCover: UIView!
    @IBOutlet weak var genericSpinner: UIActivityIndicatorView!
    
    // Settings container
    @IBOutlet weak var settingsBackground: UIView!
    @IBOutlet weak var settingsBackgroundButton: UIButton!
    @IBOutlet weak var settingsContainer: UIView!
    @IBOutlet weak var settingsContainerTop: NSLayoutConstraint!
    // Open-position constant of settingsContainerTop, set by showSettings and
    // used by the swipe-to-dismiss handler (handleSettingsPan).
    var settingsOpenConstant: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Count app opening.
        SentrySDK.metrics.count(key: "app.launch.open")
        
        // Load Bittr wallet details.
        if let deviceDict = UserDefaults.standard.value(forKey: EnvironmentConfig.cacheKey(for: "device")) as? NSDictionary {
            self.bittrWallet = CacheManager.parseDevice(deviceDict: deviceDict)
        }
        
        // Identify current dark mode.
        CacheManager.setCurrentDarkMode(darkModeIsOn: self.darkModeIsOn())
        
        // Add observers.
        NotificationCenter.default.addObserver(self, selector: #selector(newNotification), name: NSNotification.Name(rawValue: "newNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBitcoinURI), name: NSNotification.Name(rawValue: "handleBitcoinURI"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLightningURI), name: NSNotification.Name(rawValue: "handleLightningURI"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        // Set words.
        self.setWords()
        self.setBasicStyling()

        self.leftButton.accessibilityIdentifier = TestID.Nav.walletButton
        self.middleButton.accessibilityIdentifier = TestID.Nav.academyButton
        self.rightButton.accessibilityIdentifier = TestID.Nav.settingsButton

        // Swipe the settings popup down to dismiss it. Added once here (the
        // container is a persistent storyboard view); the handler no-ops while
        // the popup is closed.
        let settingsPan = UIPanGestureRecognizer(target: self, action: #selector(self.handleSettingsPan(_:)))
        // Recognise alongside the settings table's scroll pan so a drag started
        // on a row still dismisses (the table is content-height and non-scrolling).
        settingsPan.delegate = self
        self.settingsContainer.addGestureRecognizer(settingsPan)

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
            CacheManager.deleteClientInfo()
            // Show SignupVC.
            self.launchSignup(onPage: 3)
        }
    }
    
    func showPinOrSignup() {
        
        // Show Pin or Signup view upon app launch.
        if self.walletIsAvailable {
            self.signupContainerView.alpha = 0
            self.pinContainerView.alpha = 1

            // Check whether the user has been locked out of their wallet.
            // Guard against re-entry: once the removal is in progress, don't stack
            // another lockout alert + a second concurrent startWallet() task if
            // showPinOrSignup runs again.
            if CacheManager.getFailedPinAttempts() >= 10, !self.removingWalletForIncorrectPin {
                Log.info("Wallet is locked out after 10 failed PIN attempts — resuming removal on launch.")
                self.removingWalletForIncorrectPin = true
                self.fullViewCover.alpha = 0.8
                self.genericSpinner.startAnimating()
                self.showAlert(presentingController: self, title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "pinlock"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                
                // Start wallet in background.
                Task {
                    await self.startWallet()
                }
            }
        } else {
            self.signupContainerView.alpha = 1
            self.pinContainerView.alpha = 0
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if self.walletSync != nil {
            self.walletSync!.stop()
            self.walletSync = nil
        }
    }
    
    @IBAction func closeSyncTapped(_ sender: UIButton) {
        self.hideSyncView()
    }
    
    @IBAction func settingsTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        self.showSettings()
    }
    
    @IBAction func settingsBackgroundTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        self.hideSettings()
    }
    
}
