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
    
    // Connection to VCs
    var homeVC:HomeViewController?
    var infoVC:InfoViewController?
    var settingsVC:SettingsViewController?
    var signupVC:SignupViewController?
    
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
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        self.setWords()
        
        // Determine whether to show pin view or signup view.
        if CacheManager.getPin() != nil {
            // Wallet exists. Launch pin.
            self.signupAlpha = 0
            self.blackSignupAlpha = 0
            // If signupAlpha is 0, the intro animation will display the PinVC upon completion. Otherwise, it will display the SignupVC.
            
        } else {
            // No wallet exists yet. Load SignupVC ahead of intro animation completion.
            
            let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
            let newChild = storyboard.instantiateViewController(withIdentifier: "Signup")
            self.addChild(newChild)
            newChild.view.frame.size = self.signupContainerView.frame.size
            self.signupContainerView.addSubview(newChild.view)
            (newChild as! SignupViewController).coreVC = self
            newChild.didMove(toParent: self)
        }
    }
    
    @IBAction func blackSignupButtonTapped(_ sender: UIButton) {
        self.blackSignupBackground.alpha = 0
        self.statusView.alpha = 0
        self.blackSignupButton.alpha = 0
    }
    
    @objc func changeColors() {
        
        self.view.backgroundColor = Colors.getColor(color: "grey")
        self.leftWhite.backgroundColor = Colors.getColor(color: "grey")
        self.middleWhite.backgroundColor = Colors.getColor(color: "grey")
        self.rightWhite.backgroundColor = Colors.getColor(color: "grey")
        
        self.lowerTopBar.backgroundColor = Colors.getColor(color: "yellow")
        self.topBar.backgroundColor = Colors.getColor(color: "transparentyellow")
        
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
    
    func setWords() {
        
        self.statusConversion.text = Language.getWord(withID: "fetchconversionrates")
        self.statusLightning.text = Language.getWord(withID: "startlightningnode")
        self.statusBlockchain.text = Language.getWord(withID: "initiatewallet")
        self.statusSyncing.text = Language.getWord(withID: "syncwallet")
        self.statusFinal.text = Language.getWord(withID: "finalcalculations")
    }
    
}
