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
    var userHasSignedIn = false
    var walletHasSynced = false
    
    // Pin reset
    var resettingPin = false
    var removingWalletForIncorrectPin = false
    
    // Client details (bittrWallet now lives on BitcoinManager.shared)
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
        BitcoinManager.shared.bittrWallet = CacheManager.parseDevice()
        
        // Identify current dark mode.
        CacheManager.setCurrentDarkMode(darkModeIsOn: self.darkModeIsOn())
        
        // Set words.
        self.setWords()
        self.setBasicStyling()

        // Taps on the animationContainer go through it down to PinVC or SignupVC.
        self.animationContainer.isUserInteractionEnabled = false

        // Check wallet.
        self.checkWalletAvailability()
    }
    
    func checkWalletAvailability() {
        
        // Check wallet availability.
        if CacheManager.getMnemonic() != nil, CacheManager.getPin() != nil {
            // Wallet has been created. The pin container is revealed by
            // revealPinOrSignup once the launch animation's cover drops.
        } else {
            // User has not completed signup.
            // Remove cached mnemonic.
            CacheManager.deleteClientInfo()
            // Show SignupVC.
            self.launchSignup(onPage: 3)
        }
    }
    
    func revealPinOrSignup() {
        // Reveal the pin or signup container. Called from the launch
        // animation as its cover drops — NOT at viewDidLoad: revealing these
        // under the still-opaque animation cover puts their buttons in the
        // accessibility tree while taps still land on the cover, which
        // silently swallows the first interaction (and broke every Maestro
        // flow whose tap raced the intro animation).
        if CacheManager.getMnemonic() != nil, CacheManager.getPin() != nil {
            self.signupContainerView.alpha = 0
            self.pinContainerView.alpha = 1
        } else {
            self.signupContainerView.alpha = 1
            self.pinContainerView.alpha = 0
        }
    }

    func checkWalletRemoval() {
        // Upon app launch, check whether the user is locked out.
        // Or whether the user has previously tried removing the wallet.
        if CacheManager.getFailedPinAttempts() >= 10, !self.removingWalletForIncorrectPin {
            Log.info("Wallet is locked out after 10 failed PIN attempts — resuming removal on launch.")
            self.removingWalletForIncorrectPin = true
            self.fullViewCover.alpha = 0.8
            self.genericSpinner.startAnimating()
            self.showAlert(presentingController: self, title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "pinlock"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            
            // Start wallet in background.
            self.startWallet()
        } else if CacheManager.walletRemovalIsInProgress() {
            Log.info("A wallet removal was left in progress — offering to resume it on launch.")
            self.showAlert(presentingController: self, title: Language.getWord(withID: "removewalletfromdevice"), message: Language.getWord(withID: "removalinprogress"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "removewalletfromdevice")], actions: [#selector(self.cancelWalletRemoval), #selector(self.resumeWalletRemoval)])
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
