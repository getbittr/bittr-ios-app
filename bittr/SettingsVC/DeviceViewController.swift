//
//  DeviceViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/01/2024.
//

import UIKit
import LDKNode
import Sentry

class DeviceViewController: UIViewController, UNUserNotificationCenterDelegate {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerLabel: UILabel!
    
    // Language view
    @IBOutlet weak var languageView: UIView!
    @IBOutlet weak var languageLeftLabel: UILabel!
    @IBOutlet weak var languageRightLabel: UILabel!
    @IBOutlet weak var languageButton: UIButton!
    
    // Token view
    @IBOutlet weak var tokenView: UIView!
    @IBOutlet weak var tokenLabel: UILabel!
    @IBOutlet weak var tokenRightLabel: UILabel!
    
    // Public key view
    @IBOutlet weak var keyView: UIView!
    @IBOutlet weak var keyLabel: UILabel!
    @IBOutlet weak var keyRightLabel: UILabel!
    @IBOutlet weak var tokenButton: UIButton!
    @IBOutlet weak var keyButton: UIButton!
    
    @IBOutlet weak var subheaderLabel: UILabel!
    
    // Images
    @IBOutlet weak var imagesView: UIView!
    @IBOutlet weak var imagesLeftLabel: UILabel!
    @IBOutlet weak var imagesRightLabel: UILabel!
    @IBOutlet weak var imagesButton: UIButton!
    
    // Peer
    @IBOutlet weak var peerView: UIView!
    @IBOutlet weak var peerButton: UIButton!
    @IBOutlet weak var peerSpinner: UIActivityIndicatorView!
    @IBOutlet weak var peerLabel: UILabel!
    @IBOutlet weak var peerLeftLabel: UILabel!
    
    // Bittr transactions
    @IBOutlet weak var transactionsView: UIView!
    @IBOutlet weak var transactionsButton: UIButton!
    @IBOutlet weak var transactionsLabel: UILabel!
    @IBOutlet weak var transactionsLeftLabel: UILabel!
    @IBOutlet weak var transactionsSpinner: UIActivityIndicatorView!
    
    // Bittr notification
    @IBOutlet weak var notificationView: UIView!
    @IBOutlet weak var notificationsLeftLabel: UILabel!
    @IBOutlet weak var notificationLabel: UILabel!
    @IBOutlet weak var notificationButton: UIButton!
    @IBOutlet weak var notificationSpinner: UIActivityIndicatorView!
    
    // Channels
    @IBOutlet weak var channelsView: UIView!
    @IBOutlet weak var channelsLabel: UILabel!
    @IBOutlet weak var channelsLeftLabel: UILabel!
    @IBOutlet weak var channelsButton: UIButton!
    @IBOutlet weak var questionCircle: UIImageView!
    
    // Dark mode
    @IBOutlet weak var darkModeView: UIView!
    @IBOutlet weak var darkModeSwitch: UISwitch!
    @IBOutlet weak var darkModeLabel: UILabel!
    
    // Other VCs
    var coreVC:CoreViewController?
    var homeVC:HomeViewController?
    var temporaryNotificationToken = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Button titles
        self.downButton.setTitle("", for: .normal)
        self.tokenButton.setTitle("", for: .normal)
        self.keyButton.setTitle("", for: .normal)
        self.imagesButton.setTitle("", for: .normal)
        self.peerButton.setTitle("", for: .normal)
        self.transactionsButton.setTitle("", for: .normal)
        self.notificationButton.setTitle("", for: .normal)
        self.channelsButton.setTitle("", for: .normal)
        self.languageButton.setTitle("", for: .normal)
        
        // Corner radii
        self.languageView.layer.cornerRadius = 13
        self.tokenView.layer.cornerRadius = 13
        self.keyView.layer.cornerRadius = 13
        self.imagesView.layer.cornerRadius = 13
        self.peerView.layer.cornerRadius = 13
        self.transactionsView.layer.cornerRadius = 13
        self.notificationView.layer.cornerRadius = 13
        self.channelsView.layer.cornerRadius = 13
        self.darkModeView.layer.cornerRadius = 13
        
        // Notifications
        NotificationCenter.default.addObserver(self, selector: #selector(showToken), name: NSNotification.Name(rawValue: "showtoken"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        if CacheManager.darkModeIsOn() {
            self.darkModeSwitch.setOn(true, animated: false)
        }
        
        self.changeColors()
        self.setWords()
        
        if CacheManager.getLanguage() == "en_US" {
            self.languageRightLabel.text = "English"
        }
        
        Task {
            do {
                if LightningNodeService.shared.ldkNode != nil {
                    let channels = try await LightningNodeService.shared.listChannels()
                    print("Channels: \(channels.count)")
                    self.channelsLabel.text = "\(channels.count)"
                } else {
                    self.channelsLabel.text = "Syncing"
                }
            } catch {
                print("Error listing channels: \(error.localizedDescription)")
                self.channelsLabel.text = "0"
            }
        }
    }

    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    @IBAction func languageButtonTapped(_ sender: UIButton) {
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let englishOption = UIAlertAction(title: "English (US)", style: .default) { (action) in
            CacheManager.changeLanguage("en_US")
        }
        let cancelAction = UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil)
        actionSheet.addAction(englishOption)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true, completion: nil)
    }
    
    @IBAction func tokenButtonTapped(_ sender: UIButton) {
        
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings { (settings) in
            
            if settings.authorizationStatus != .authorized {
                // User hasn't accepted push notifications.
                
                current.delegate = self
                current.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    
                    print("Permission granted: \(granted)")
                    guard granted else {return}
                    
                    // Double check that the preference is now authorized.
                    current.getNotificationSettings { (settings) in
                        print("Notification settings: \(settings)")
                        guard settings.authorizationStatus == .authorized else {return}
                        DispatchQueue.main.async {
                            // Register for notifications.
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
            } else {
                // User has accepted push notifications.
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    @objc func showToken(notification:NSNotification) {
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let notificationToken = userInfo["token"] as? String {
                self.temporaryNotificationToken = notificationToken
                self.showAlert(presentingController: self, title: Language.getWord(withID: "devicetoken"), message: "\(notificationToken)", buttons: [Language.getWord(withID: "copy"), Language.getWord(withID: "close")], actions: [#selector(self.copyNotificationToken), nil])
            }
        }
    }
    
    @objc func copyNotificationToken() {
        self.hideAlert()
        UIPasteboard.general.string = self.temporaryNotificationToken
        self.temporaryNotificationToken = ""
    }
    
    @IBAction func keyButtonTapped(_ sender: UIButton) {
        let lightningKey = LightningNodeService.shared.nodeId()
        self.showAlert(presentingController: self, title: Language.getWord(withID: "publickey"), message: "\(lightningKey)", buttons: [Language.getWord(withID: "copy"), Language.getWord(withID: "close")], actions: [#selector(self.copyLightningKey), nil])
    }
    
    @objc func copyLightningKey() {
        self.hideAlert()
        let lightningKey = LightningNodeService.shared.nodeId()
        UIPasteboard.general.string = lightningKey
    }
    
    @IBAction func imagesButtonTapped(_ sender: UIButton) {
        self.showAlert(presentingController: self, title: Language.getWord(withID: "cachedimages"), message: Language.getWord(withID: "cachedimages1"), buttons: [Language.getWord(withID: "remove"), Language.getWord(withID: "cancel")], actions: [#selector(self.emptyImageCache), nil])
    }
    
    @objc func emptyImageCache() {
        self.hideAlert()
        CacheManager.emptyImage()
        self.showAlert(presentingController: self, title: Language.getWord(withID: "cacheemptied"), message: Language.getWord(withID: "cachedimages2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func peerButtonTapped(_ sender: UIButton) {
        
        self.peerLabel.alpha = 1
        self.peerSpinner.stopAnimating()
        self.peerButton.isUserInteractionEnabled = true
        
        Task {
            do {
                let peers = try await LightningNodeService.shared.listPeers()
                print(peers)
                if peers.count == 1 {
                    if peers[0].isConnected == true {
                        print("Did successfully check peer connection.")
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    } else {
                        print("Not connected to peer.")
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer3"), buttons: [Language.getWord(withID: "connect"), Language.getWord(withID: "close")], actions: [#selector(self.reconnectToPeer), nil])
                    }
                } else {
                    print("Not connected to peer.")
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer3"), buttons: [Language.getWord(withID: "connect"), Language.getWord(withID: "close")], actions: [#selector(self.reconnectToPeer), nil])
                }
            } catch {
                print("Error listing peers: \(error.localizedDescription)")
                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer3"), buttons: [Language.getWord(withID: "connect"), Language.getWord(withID: "close")], actions: [#selector(self.reconnectToPeer), nil])
            }
        }
    }
    
    @IBAction func transactionsButtonTapped(_ sender: UIButton) {
        
        if let actualHomeVC = self.homeVC {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrtransactions"), message: Language.getWord(withID: "bittrtransactions2"), buttons: [Language.getWord(withID: "check"), Language.getWord(withID: "close")], actions: [#selector(self.checkBittrTransactions), nil])
        }
    }
    
    @objc func checkBittrTransactions() {
        self.hideAlert()
        
        self.transactionsLabel.alpha = 0
        self.transactionsSpinner.startAnimating()
        Task {
            if await self.homeVC!.fetchTransactionData(txIds: [String](), sendAll: true) == true {
                DispatchQueue.main.async {
                    self.transactionsLabel.alpha = 1
                    self.transactionsSpinner.stopAnimating()
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrtransactions"), message: Language.getWord(withID: "bittrtransactions3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.transactionsLabel.alpha = 1
                    self.transactionsSpinner.stopAnimating()
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrtransactions"), message: Language.getWord(withID: "bittrtransactions4"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            }
        }
    }
    
    @IBAction func notificationButtonTapped(_ sender: UIButton) {
        
        if let actualHomeVC = self.homeVC {
            if let actualCoreVC = actualHomeVC.coreVC {
                if actualCoreVC.varSpecialData != nil {
                    actualCoreVC.pendingLabel.text = Language.getWord(withID: "receivingpayment")
                    actualCoreVC.pendingSpinner.startAnimating()
                    actualCoreVC.pendingView.alpha = 1
                    actualCoreVC.blackSignupBackground.alpha = 0.2
                    actualCoreVC.facilitateNotificationPayout()
                    self.dismiss(animated: true)
                } else {
                    if let actualSpecialData = CacheManager.getLatestNotification() {
                        actualCoreVC.varSpecialData = actualSpecialData
                        actualCoreVC.pendingLabel.text = Language.getWord(withID: "receivingpayment")
                        actualCoreVC.pendingSpinner.startAnimating()
                        actualCoreVC.pendingView.alpha = 1
                        actualCoreVC.blackSignupBackground.alpha = 0.2
                        actualCoreVC.facilitateNotificationPayout()
                        self.dismiss(animated: true)
                    } else {
                        self.showNotificationAlert()
                    }
                }
            } else {
                self.showNotificationAlert()
            }
        } else {
            self.showNotificationAlert()
        }
    }
    
    func showNotificationAlert() {
        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrnotification"), message: Language.getWord(withID: "bittrnotification2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @objc func reconnectToPeer() {
        self.hideAlert()
        
        self.peerLabel.alpha = 0
        self.peerSpinner.startAnimating()
        self.peerButton.isUserInteractionEnabled = false
        
        // TODO: Public?
        // .testnet and .bitcoin
        let nodeIds = ["03a7ff144e9b3797a6a232d8f06043245e98fbb37ff892cb072d21d99dd98d473e", "03a7ff144e9b3797a6a232d8f06043245e98fbb37ff892cb072d21d99dd98d473e"]
        let addresses = ["31.58.51.17:9735", "31.58.51.17:9735"]
        
        // Connect to Lightning peer.
        let nodeId = nodeIds[UserDefaults.standard.value(forKey: "envkey") as? Int ?? 1] // Extract this from your peer string
        let address = addresses[UserDefaults.standard.value(forKey: "envkey") as? Int ?? 1] // Extract this from your peer string
        
        let connectTask = Task {
            do {
                try await LightningNodeService.shared.connect(
                    nodeId: nodeId,
                    address: address,
                    persist: true
                )
                try Task.checkCancellation()
                if Task.isCancelled == true {
                    print("Did connect to peer, but too late.")
                    return false
                }
                print("Did connect to peer.")
                return true
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                    print("Can't connect to peer: \(errorString)")
                    SentrySDK.capture(error: error)
                }
                return false
            } catch {
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                    print("Can't connect to peer: No error message.")
                    SentrySDK.capture(error: error)
                }
                return false
            }
        }
        
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(5) * NSEC_PER_SEC)
            connectTask.cancel()
            print("Connecting to peer takes too long.")
            self.peerButtonTapped(self.peerButton)
        }
        
        Task.init {
            let result = await connectTask.value
            timeoutTask.cancel()
            self.peerButtonTapped(self.peerButton)
        }
    }
    
    @IBAction func channelsButtonTapped(_ sender: UIButton) {
        
        self.coreVC!.launchQuestion(question: Language.getWord(withID: "lightningchannels"), answer: Language.getWord(withID: "lightningexplanation1"), type: "lightningexplanation")
    }
    
    @IBAction func darkModeSwitched(_ sender: UISwitch) {
        if sender.isOn {
            // Dark mode has been switched on.
            CacheManager.updateDarkMode(isOn: true)
        } else {
            // Dark mode has been switched off.
            CacheManager.updateDarkMode(isOn: false)
        }
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecolors"), object: nil, userInfo: nil) as Notification)
    }
    
    @objc func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        
        self.darkModeView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.languageView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.tokenView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.keyView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.peerView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.transactionsView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.notificationView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.channelsView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.imagesView.backgroundColor = Colors.getColor("white0.7orblue2")
        
        self.subheaderLabel.textColor = Colors.getColor("blackorwhite")
        
        self.darkModeLabel.textColor = Colors.getColor("blackorwhite")
        self.languageLeftLabel.textColor = Colors.getColor("blackorwhite")
        self.languageRightLabel.textColor = Colors.getColor("blackorwhite")
        self.tokenLabel.textColor = Colors.getColor("blackorwhite")
        self.tokenRightLabel.textColor = Colors.getColor("blackorwhite")
        self.keyLabel.textColor = Colors.getColor("blackorwhite")
        self.keyRightLabel.textColor = Colors.getColor("blackorwhite")
        self.peerLeftLabel.textColor = Colors.getColor("blackorwhite")
        self.peerLabel.textColor = Colors.getColor("blackorwhite")
        self.transactionsLeftLabel.textColor = Colors.getColor("blackorwhite")
        self.transactionsLabel.textColor = Colors.getColor("blackorwhite")
        self.notificationsLeftLabel.textColor = Colors.getColor("blackorwhite")
        self.notificationLabel.textColor = Colors.getColor("blackorwhite")
        self.channelsLeftLabel.textColor = Colors.getColor("blackorwhite")
        self.channelsLabel.textColor = Colors.getColor("blackorwhite")
        self.imagesLeftLabel.textColor = Colors.getColor("blackorwhite")
        self.imagesRightLabel.textColor = Colors.getColor("blackorwhite")
        
        self.questionCircle.tintColor = Colors.getColor("blackorwhite")
        
    }
    
    @objc func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "devicedetails2")
        self.subheaderLabel.text = Language.getWord(withID: "accessdetails")
        self.darkModeLabel.text = "🌙  " + Language.getWord(withID: "darkmode")
        self.tokenLabel.text = "📱  " + Language.getWord(withID: "devicetoken")
        self.tokenRightLabel.text = Language.getWord(withID: "fetch")
        self.keyLabel.text = "🗝️  " + Language.getWord(withID: "publickey")
        self.keyRightLabel.text = Language.getWord(withID: "fetch")
        self.peerLeftLabel.text = "🔗  " + Language.getWord(withID: "bittrpeer")
        self.peerLabel.text = Language.getWord(withID: "check")
        self.transactionsLeftLabel.text = "💰  " + Language.getWord(withID: "bittrpurchases")
        self.transactionsLabel.text = Language.getWord(withID: "check")
        self.notificationsLeftLabel.text = "📬  " + Language.getWord(withID: "bittrnotification")
        self.notificationLabel.text = Language.getWord(withID: "retry")
        self.channelsLeftLabel.text = "⚡️  " + Language.getWord(withID: "lightningchannels2")
        self.imagesLeftLabel.text = "🎞️  " + Language.getWord(withID: "cachedimages")
        self.imagesRightLabel.text = Language.getWord(withID: "empty")
        self.languageLeftLabel.text = "🌍  " + Language.getWord(withID: "language")
    }
    
}
