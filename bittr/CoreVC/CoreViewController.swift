//
//  CoreViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/03/2023.
//

import UIKit
import LDKNode
//import KeychainSwift
import BitcoinDevKit
import LDKNodeFFI

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
    
    //let keychain = KeychainSwift()
    
    var signupAlpha:CGFloat = 1
    var blackSignupAlpha:CGFloat = 0.3
    
    var didBecomeVisible = false
    var needsToHandleNotification = false
    var lightningNotification:NSNotification?
    
    @IBOutlet weak var pendingView: UIView!
    @IBOutlet weak var pendingSpinner: UIActivityIndicatorView!
    var varSpecialData:[String: Any]?
    
    var homeVC:HomeViewController?
    
    // QuestionVC
    var tappedQuestion = ""
    var tappedAnswer = ""
    var tappedType:String?
    
    var didStartNode = false
    
    var receivedBittrTransaction:Transaction?
    var eurValue:CGFloat = 0.0
    var chfValue:CGFloat = 0.0
    
    var bittrChannel:Channel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        selectedView.layer.cornerRadius = 13
        leftWhite.layer.cornerRadius = 13
        middleWhite.layer.cornerRadius = 13
        rightWhite.layer.cornerRadius = 13
        pendingView.layer.cornerRadius = 13
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
        
        
        // Determine whether to show pin view or signup view.
        if let actualPin = CacheManager.getPin() {
            // Wallet exists. Launch pin.
            signupAlpha = 0
            blackSignupAlpha = 0
            
        } else {
            // No wallet exists yet. Go through signup.
        }
    }
    
}
