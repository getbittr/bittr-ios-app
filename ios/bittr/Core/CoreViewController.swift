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
    var userHasSignedIn = false
    var walletHasSynced = false
    // True while checkWalletAvailability is waiting for the Keychain to become
    // readable (device locked / transient read error) before it decides.
    private var isAwaitingProtectedData = false
    
    // Pin reset
    var resettingPin = false
    var removingWalletForIncorrectPin = false
    var isRemovalInFlight = false

    // True while continueStartWallet's post-start work is running. Several
    // startWallet callers can be attached to a single node start, and they all
    // get told when it finishes — but that work is global, not per-caller.
    var isContinuingStartWallet = false
    
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
        SentryManager.countMetric("app.launch.open")
        
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
        
        // Decide which screen to show based on whether a wallet exists. The
        // containers are revealed here, at viewDidLoad, and stay interactable
        // during the launch animation: the animation cover passes taps
        // through (its isUserInteractionEnabled is false), so the PIN/signup
        // screen is usable while it becomes visible — and automation taps
        // can't be swallowed by the cover.
        switch CacheManager.walletSecretsPresence() {
        case .present:
            Log.info("Wallet is available.")
            self.finishAwaitingProtectedDataIfNeeded()
            self.signupContainerView.alpha = 0
            self.pinContainerView.alpha = 1
            
        case .absent:
            Log.info("No wallet on this device.")
            self.finishAwaitingProtectedDataIfNeeded()
            self.signupContainerView.alpha = 1
            self.pinContainerView.alpha = 0
            // Clear any stale cached client data and show the create-wallet flow.
            CacheManager.deleteClientInfo()
            self.launchSignup(onPage: 3)
            
        case .unavailable:
            Log.info("The Keychain could not be read.")
            self.presentKeychainUnavailable()
        }
    }
    
    private func presentKeychainUnavailable() {
        Log.info("Wallet secrets unavailable — showing the retry prompt.")
        self.signupContainerView.alpha = 0
        self.pinContainerView.alpha = 1
        self.fullViewCover.alpha = 0.8
        self.genericSpinner.startAnimating()

        if !self.isAwaitingProtectedData {
            self.isAwaitingProtectedData = true
            NotificationCenter.default.addObserver(self, selector: #selector(self.retryReadingKeychain), name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        }

        self.showAlert(presentingController: self,
                       title: Language.getWord(withID: "keychainunavailabletitle"),
                       message: Language.getWord(withID: "keychainunavailable"),
                       buttons: [Language.getWord(withID: "tryagain")],
                       actions: [#selector(self.retryReadingKeychain)])
    }
    
    private func finishAwaitingProtectedDataIfNeeded() {
        guard self.isAwaitingProtectedData else { return }
        self.isAwaitingProtectedData = false
        NotificationCenter.default.removeObserver(self, name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        self.fullViewCover.alpha = 0
        self.genericSpinner.stopAnimating()
    }
    
    @objc private func retryReadingKeychain() {
        self.hideAlert()
        self.checkWalletAvailability()
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
