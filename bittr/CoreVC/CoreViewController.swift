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

    // 0 is Dev. 1 is Prod. ALSO change the network in LightningNodeService.
    var devEnvironment = 1
    
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
    
    // Container views for PinVC and SignupVC
    @IBOutlet weak var pinContainerView: UIView!
    @IBOutlet weak var signupContainerView: UIView!
    @IBOutlet weak var signupBottom: NSLayoutConstraint!
    @IBOutlet weak var blackSignupBackground: UIView!
    @IBOutlet weak var blackSignupButton: UIButton!
    @IBOutlet weak var pinBottom: NSLayoutConstraint!
    var signupAlpha:CGFloat = 1
    var blackSignupAlpha:CGFloat = 0.3
    
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
    
    // Connection to HomeVC
    var homeVC:HomeViewController?
    
    // Elements for QuestionVC
    var tappedQuestion = ""
    var tappedAnswer = ""
    var tappedType:String?
    
    // Syncing status
    var didStartNode = false
    var walletHasSynced = false
    var syncStatus = "startnode"
    
    // Conversion rates
    var eurValue:CGFloat = 0.0
    var chfValue:CGFloat = 0.0
    
    // Channel details
    var bittrChannel:Channel?
    
    // Client details
    var client = Client()
    
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
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Save environment key for switching between Dev and Production.
        UserDefaults.standard.set(devEnvironment, forKey: "envkey")
        
        // Set corner radii and button titles.
        selectedView.layer.cornerRadius = 13
        leftWhite.layer.cornerRadius = 13
        middleWhite.layer.cornerRadius = 13
        rightWhite.layer.cornerRadius = 13
        pendingView.layer.cornerRadius = 13
        statusView.layer.cornerRadius = 13
        leftButton.setTitle("", for: .normal)
        middleButton.setTitle("", for: .normal)
        rightButton.setTitle("", for: .normal)
        yellowcurve.alpha = 0.85
        
        // Add observers.
        NotificationCenter.default.addObserver(self, selector: #selector(hideSignup), name: NSNotification.Name(rawValue: "restorewallet"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(startLightning), name: NSNotification.Name(rawValue: "startlightning"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePaymentNotification), name: NSNotification.Name(rawValue: "handlepaymentnotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBittrNotification), name: NSNotification.Name(rawValue: "handlebittrnotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopLightning), name: NSNotification.Name(rawValue: "stoplightning"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(launchQuestion), name: NSNotification.Name(rawValue: "question"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateSync), name: NSNotification.Name(rawValue: "updatesync"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ldkEventReceived), name: NSNotification.Name(rawValue: "ldkEventReceived"), object: nil)
        
        // Determine whether to show pin view or signup view.
        if let actualPin = CacheManager.getPin() {
            // Wallet exists. Launch pin.
            signupAlpha = 0
            blackSignupAlpha = 0
        } else {
            // No wallet exists yet. Go through signup.
            let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
            let newChild = storyboard.instantiateViewController(withIdentifier: "Signup")
            self.addChild(newChild)
            newChild.view.frame.size = self.signupContainerView.frame.size
            self.signupContainerView.addSubview(newChild.view)
            newChild.didMove(toParent: self)
        }
    }
    
    @IBAction func blackSignupButtonTapped(_ sender: UIButton) {
        self.blackSignupBackground.alpha = 0
        self.statusView.alpha = 0
        self.blackSignupButton.alpha = 0
    }
    
}
