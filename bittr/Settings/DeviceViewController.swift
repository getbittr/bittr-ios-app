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
    @IBOutlet weak var headerView: UIView!
    
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
    var homeVC:HomeViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        tokenButton.setTitle("", for: .normal)
        keyButton.setTitle("", for: .normal)
        imagesButton.setTitle("", for: .normal)
        peerButton.setTitle("", for: .normal)
        transactionsButton.setTitle("", for: .normal)
        notificationButton.setTitle("", for: .normal)
        channelsButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        tokenView.layer.cornerRadius = 13
        keyView.layer.cornerRadius = 13
        imagesView.layer.cornerRadius = 13
        peerView.layer.cornerRadius = 13
        transactionsView.layer.cornerRadius = 13
        notificationView.layer.cornerRadius = 13
        channelsView.layer.cornerRadius = 13
        darkModeView.layer.cornerRadius = 13
        
        NotificationCenter.default.addObserver(self, selector: #selector(showToken), name: NSNotification.Name(rawValue: "showtoken"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        if CacheManager.darkModeIsOn() {
            self.darkModeSwitch.setOn(true, animated: false)
        }
        
        self.changeColors()
        
        Task {
            do {
                let channels = try await LightningNodeService.shared.listChannels()
                print("Channels: \(channels.count)")
                self.channelsLabel.text = "\(channels.count)"
            } catch {
                print("Error listing channels: \(error.localizedDescription)")
                self.channelsLabel.text = "0"
            }
        }
    }

    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
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
                let alert = UIAlertController(title: "Device token", message: "\(notificationToken)", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Copy", style: .default, handler: { _ in
                    // Copy the invoice to the clipboard
                    UIPasteboard.general.string = notificationToken
                }))
                alert.addAction(UIAlertAction(title: Language.getWord(withID: "close"), style: .cancel, handler: nil))
                self.present(alert, animated: true)
            }
        }
    }
    
    @IBAction func keyButtonTapped(_ sender: UIButton) {
        
        let lightningKey = LightningNodeService.shared.nodeId()
        
        let alert = UIAlertController(title: "Public key", message: "\(lightningKey)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Copy", style: .default, handler: { _ in
            // Copy the invoice to the clipboard
            UIPasteboard.general.string = lightningKey
        }))
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "close"), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @IBAction func imagesButtonTapped(_ sender: UIButton) {
        
        let alert = UIAlertController(title: "Cached images", message: "Are you sure you want to remove your cached images?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Remove", style: .default, handler: { _ in
            // Copy the invoice to the clipboard
            CacheManager.emptyImage()
            let alert = UIAlertController(title: "Cache emptied", message: "Any cached images have been removed.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
            self.present(alert, animated: true)
        }))
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @IBAction func peerButtonTapped(_ sender: UIButton) {
        
        self.peerLabel.alpha = 1
        self.peerSpinner.stopAnimating()
        self.peerButton.isUserInteractionEnabled = true
        
        Task {
            do {
                let peers = try await LightningNodeService.shared.listPeers()
                if peers.count == 1 {
                    if peers[0].isConnected == true {
                        print("Did successfully check peer connection.")
                        
                        let alert = UIAlertController(title: "Bittr peer", message: "You're connected to Bittr.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
                        self.present(alert, animated: true)
                    } else {
                        print("Not connected to peer.")
                        
                        let alert = UIAlertController(title: "Bittr peer", message: "You're not connected to Bittr.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Connect", style: .default, handler: { _ in
                            self.reconnectToPeer()
                        }))
                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "close"), style: .cancel, handler: nil))
                        self.present(alert, animated: true)
                    }
                } else {
                    print("Not connected to peer.")
                    
                    let alert = UIAlertController(title: "Bittr peer", message: "You're not connected to Bittr.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Connect", style: .default, handler: { _ in
                        self.reconnectToPeer()
                    }))
                    alert.addAction(UIAlertAction(title: Language.getWord(withID: "close"), style: .cancel, handler: nil))
                    self.present(alert, animated: true)
                }
            } catch {
                print("Error listing peers: \(error.localizedDescription)")
                
                let alert = UIAlertController(title: "Bittr peer", message: "You're not connected to Bittr.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Connect", style: .default, handler: { _ in
                    self.reconnectToPeer()
                }))
                alert.addAction(UIAlertAction(title: Language.getWord(withID: "close"), style: .cancel, handler: nil))
                self.present(alert, animated: true)
            }
        }
    }
    
    @IBAction func transactionsButtonTapped(_ sender: UIButton) {
        
        if let actualHomeVC = self.homeVC {
            let alert = UIAlertController(title: "Bittr transactions", message: "Would you like to fetch additional information about your Bittr purchases?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Check", style: .default, handler: { _ in
                self.transactionsLabel.alpha = 0
                self.transactionsSpinner.startAnimating()
                Task {
                    if await actualHomeVC.fetchTransactionData(txIds: [String](), sendAll: true) == true {
                        DispatchQueue.main.async {
                            self.transactionsLabel.alpha = 1
                            self.transactionsSpinner.stopAnimating()
                            let alert = UIAlertController(title: "Bittr transactions", message: "New information has been received. Your transactions have been refreshed.", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
                            self.present(alert, animated: true)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.transactionsLabel.alpha = 1
                            self.transactionsSpinner.stopAnimating()
                            let alert = UIAlertController(title: "Bittr transactions", message: "No new information is available.", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
                            self.present(alert, animated: true)
                        }
                    }
                }
            }))
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "close"), style: .cancel, handler: nil))
            self.present(alert, animated: true)
        }
    }
    
    @IBAction func notificationButtonTapped(_ sender: UIButton) {
        
        if let actualHomeVC = self.homeVC {
            if let actualCoreVC = actualHomeVC.coreVC {
                if let actualSpecialData = actualCoreVC.varSpecialData {
                    actualCoreVC.pendingLabel.text = "receiving payment"
                    actualCoreVC.pendingSpinner.startAnimating()
                    actualCoreVC.pendingView.alpha = 1
                    actualCoreVC.blackSignupBackground.alpha = 0.2
                    actualCoreVC.facilitateNotificationPayout(specialData: actualSpecialData)
                    self.dismiss(animated: true)
                } else {
                    if let actualSpecialData = CacheManager.getLatestNotification() {
                        actualCoreVC.varSpecialData = actualSpecialData
                        actualCoreVC.pendingLabel.text = "receiving payment"
                        actualCoreVC.pendingSpinner.startAnimating()
                        actualCoreVC.pendingView.alpha = 1
                        actualCoreVC.blackSignupBackground.alpha = 0.2
                        actualCoreVC.facilitateNotificationPayout(specialData: actualSpecialData)
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
        let alert = UIAlertController(title: "Bittr notification", message: "There is no notification available for handling.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    func reconnectToPeer() {
        
        self.peerLabel.alpha = 0
        self.peerSpinner.startAnimating()
        self.peerButton.isUserInteractionEnabled = false
        
        // TODO: Public?
        // .testnet and .bitcoin
        let nodeIds = ["026d74bf2a035b8a14ea7c59f6a0698d019720e812421ec02762fdbf064c3bc326", "036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12"]
        let addresses = ["109.205.181.232:9735", "86.104.228.24:9735"]
        
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
        
        let notificationDict:[String: Any] = ["question":"lightning channels","answer":"To send and receive Bitcoin Lightning payments, you need to have at least one Lightning channel with anyone.\n\nTo open a channel with Bittr, buy bitcoin worth up to 100 Swiss Francs or Euros. Check your wallet's Buy section or getbittr.com for all information.","type":"lightningexplanation"]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
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
        
        self.view.backgroundColor = Colors.getColor(color: "yellowandgrey")
        
        self.darkModeView.backgroundColor = Colors.getColor(color: "lighterbutton")
        self.tokenView.backgroundColor = Colors.getColor(color: "lighterbutton")
        self.keyView.backgroundColor = Colors.getColor(color: "lighterbutton")
        self.peerView.backgroundColor = Colors.getColor(color: "lighterbutton")
        self.transactionsView.backgroundColor = Colors.getColor(color: "lighterbutton")
        self.notificationView.backgroundColor = Colors.getColor(color: "lighterbutton")
        self.channelsView.backgroundColor = Colors.getColor(color: "lighterbutton")
        self.imagesView.backgroundColor = Colors.getColor(color: "lighterbutton")
        
        self.subheaderLabel.textColor = Colors.getColor(color: "black")
        
        self.darkModeLabel.textColor = Colors.getColor(color: "black")
        self.tokenLabel.textColor = Colors.getColor(color: "black")
        self.tokenRightLabel.textColor = Colors.getColor(color: "black")
        self.keyLabel.textColor = Colors.getColor(color: "black")
        self.keyRightLabel.textColor = Colors.getColor(color: "black")
        self.peerLeftLabel.textColor = Colors.getColor(color: "black")
        self.peerLabel.textColor = Colors.getColor(color: "black")
        self.transactionsLeftLabel.textColor = Colors.getColor(color: "black")
        self.transactionsLabel.textColor = Colors.getColor(color: "black")
        self.notificationsLeftLabel.textColor = Colors.getColor(color: "black")
        self.notificationLabel.textColor = Colors.getColor(color: "black")
        self.channelsLeftLabel.textColor = Colors.getColor(color: "black")
        self.channelsLabel.textColor = Colors.getColor(color: "black")
        self.imagesLeftLabel.textColor = Colors.getColor(color: "black")
        self.imagesRightLabel.textColor = Colors.getColor(color: "black")
        
        self.questionCircle.tintColor = Colors.getColor(color: "black")
        
    }
    
}
