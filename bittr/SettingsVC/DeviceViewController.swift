//
//  DeviceViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/01/2024.
//

import UIKit
import LDKNode
import Sentry

class DeviceViewController: UIViewController, UNUserNotificationCenterDelegate, UITableViewDelegate, UITableViewDataSource {
    
    // Table view
    @IBOutlet weak var deviceTableView: UITableView!
    @IBOutlet weak var deviceTableViewHeight: NSLayoutConstraint!
    
    // Table items
    let deviceItems = [
        ["id":"darkmode", "label":Language.getWord(withID: "darkmode"), "button":"", "icon":"moon.fill"],
        ["id":"language", "label":Language.getWord(withID: "language"), "button":"", "icon":"globe.europe.africa.fill"],
        ["id":"devicetoken", "label":Language.getWord(withID: "devicetoken"), "button":Language.getWord(withID: "fetch"), "icon":"iphone"],
        ["id":"publickey", "label":Language.getWord(withID: "publickey"), "button":Language.getWord(withID: "fetch"), "icon":"key.horizontal.fill"],
        ["id":"bittrpeer", "label":Language.getWord(withID: "bittrpeer"), "button":Language.getWord(withID: "check"), "icon":"point.topleft.down.to.point.bottomright.curvepath.fill"],
        ["id":"purchases", "label":Language.getWord(withID: "bittrpurchases"), "button":Language.getWord(withID: "check"), "icon":"banknote.fill"],
        ["id":"notification", "label":Language.getWord(withID: "bittrnotification"), "button":Language.getWord(withID: "retry"), "icon":"envelope.fill"],
        ["id":"lightningchannels", "label":Language.getWord(withID: "lightningchannels2"), "button":"", "icon":"bolt.fill"],
        ["id":"cache", "label":Language.getWord(withID: "cachedimages"), "button":Language.getWord(withID: "empty"), "icon":"photo.fill"]
    ]
    
    // Header
    @IBOutlet weak var subheaderLabel: UILabel!
    
    // Other VCs
    var coreVC:CoreViewController?
    var homeVC:HomeViewController?
    var tappedCell:DeviceTableViewCell?
    var temporaryNotificationToken = ""
    var channelsCount:String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Table view
        self.deviceTableView.delegate = self
        self.deviceTableView.dataSource = self
        self.deviceTableViewHeight.constant = CGFloat(self.deviceItems.count * 55)
        
        // Notifications
        NotificationCenter.default.addObserver(self, selector: #selector(showToken), name: NSNotification.Name(rawValue: "showtoken"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        // Set colors and language.
        self.changeColors()
        self.setWords()
    }
    
    func syncChannels() {
        if BitcoinManager.shared.ldkNode != nil {
            let channels = BitcoinManager.shared.listChannels()
            Log.info("Channels: \(channels.count)")
            self.channelsCount = "\(channels.count)"
            self.deviceTableView.reloadData()
        } else {
            self.channelsCount = "Syncing"
            self.deviceTableView.reloadData()
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.deviceItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if let cell = tableView.dequeueReusableCell(withIdentifier: "DeviceCell", for: indexPath) as? DeviceTableViewCell {
            
            cell.deviceVC = self
            cell.changeColors()
            
            cell.cellIcon.image = UIImage(systemName: self.deviceItems[indexPath.row]["icon"] ?? "bitcoinsign.circle")
            cell.cellTitle.text = self.deviceItems[indexPath.row]["label"] ?? ""
            cell.buttonLabel.text = self.deviceItems[indexPath.row]["button"] ?? ""
            
            let cellTag = self.deviceItems[indexPath.row]["id"]!
            cell.cellButton.accessibilityIdentifier = cellTag
            
            cell.hideDarkMode()
            switch cellTag {
            case "language":
                if CacheManager.getLanguage() == "en_US" {
                    cell.buttonLabel.text = "English"
                }
            case "lightningchannels":
                if self.channelsCount == nil {
                    self.syncChannels()
                } else {
                    cell.buttonLabel.text = self.channelsCount!
                }
            case "darkmode":
                cell.showDarkMode()
            default: break
            }
            
            return cell
        } else {
            return UITableViewCell()
        }
    }
    
    func changeLanguage() {
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let englishOption = UIAlertAction(title: "English (US)", style: .default) { (action) in
            CacheManager.changeLanguage("en_US")
        }
        let cancelAction = UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil)
        actionSheet.addAction(englishOption)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true, completion: nil)
    }
    
    func getToken() {
        
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings { (settings) in
            
            if settings.authorizationStatus != .authorized {
                // User hasn't accepted push notifications.
                
                current.delegate = self
                current.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    
                    Log.info("Permission granted: \(granted)")
                    guard granted else {return}
                    
                    // Double check that the preference is now authorized.
                    current.getNotificationSettings { (settings) in
                        Log.info("Notification settings: \(settings)")
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
    
    func getPublicKey() {
        if let lightningKey = BitcoinManager.shared.nodeId() {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "publickey"), message: "\(lightningKey)", buttons: [Language.getWord(withID: "copy"), Language.getWord(withID: "close")], actions: [#selector(self.copyLightningKey), nil])
        } else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "publickey"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    @objc func copyLightningKey() {
        self.hideAlert()
        let lightningKey = BitcoinManager.shared.nodeId()!
        UIPasteboard.general.string = lightningKey
    }
    
    func imagesButtonTapped() {
        self.showAlert(presentingController: self, title: Language.getWord(withID: "cachedimages"), message: Language.getWord(withID: "cachedimages1"), buttons: [Language.getWord(withID: "remove"), Language.getWord(withID: "cancel")], actions: [#selector(self.emptyImageCache), nil])
    }
    
    @objc func emptyImageCache() {
        self.hideAlert()
        CacheManager.emptyImage()
        self.showAlert(presentingController: self, title: Language.getWord(withID: "cacheemptied"), message: Language.getWord(withID: "cachedimages2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    func checkPeerConnection() {
        
        self.tappedCell?.stopAnimating()
        
        Task {
            if await self.isConnectedToPeer() {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            } else {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer3"), buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "connect")], actions: [nil, #selector(self.reconnectToPeer)])
            }
        }
    }
    
    @objc func reconnectToPeer() {
        self.hideAlert()
        
        self.tappedCell?.animateCell()
        
        Task {
            await BitcoinManager.shared.didEstablishPeerConnection()
            self.checkPeerConnection()
        }
    }
    
    func checkPurchases() {
        
        if self.homeVC != nil {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrtransactions"), message: Language.getWord(withID: "bittrtransactions2"), buttons: [Language.getWord(withID: "check"), Language.getWord(withID: "close")], actions: [#selector(self.checkBittrTransactions), nil])
        }
    }
    
    @objc func checkBittrTransactions() {
        self.hideAlert()
        
        self.tappedCell?.animateCell()
        
        Task {
            let didReceiveNewInformation = await self.homeVC!.getBittrTransactionDetails(sendAll: true)
            DispatchQueue.main.async {
                self.tappedCell?.stopAnimating()
                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrtransactions"), message: Language.getWord(withID: didReceiveNewInformation ? "bittrtransactions3" : "bittrtransactions4"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        }
    }
    
    func checkNotification() {
        if self.homeVC?.coreVC != nil, (self.homeVC!.coreVC!.varSpecialData != nil || CacheManager.getLatestNotification() != nil) {
            if self.homeVC!.coreVC!.varSpecialData == nil {
                self.homeVC!.coreVC!.varSpecialData = CacheManager.getLatestNotification()!
            }
            self.homeVC!.coreVC!.pendingLabel.text = Language.getWord(withID: "receivingpayment")
            self.homeVC!.coreVC!.showPendingView()
            self.homeVC!.coreVC!.facilitateNotificationPayout()
            self.dismiss(animated: true)
        } else {
            self.showNotificationAlert()
        }
    }
    
    func showNotificationAlert() {
        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrnotification"), message: Language.getWord(withID: "bittrnotification2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    func checkChannels() {
        
        // TEMPORARY: You can uncomment this code to have the bittr app make a connection and open a channel (in regtest)
        // Task {
        //     do {
        //         print("[TEMP] Opening channel to 0251f466be01d4fcf7d98b62d02e6bac875f36a67f7a433a38e4aab7f24491716d")
        //         let nodeId = "0251f466be01d4fcf7d98b62d02e6bac875f36a67f7a433a38e4aab7f24491716d"
        //         let address = "31.58.51.17:19735"
        //         let channelAmountSats: UInt64 = 1_000_000
        //         let pushAmountSats: UInt64 = 500_000_000
                
        //         // First connect to the peer
        //         try await BitcoinManager.shared.connect(
        //             nodeId: nodeId,
        //             address: address,
        //             persist: true
        //         )
        //         print("[TEMP] Connected to peer successfully")
                
        //         // Wait a moment for connection to establish
        //         try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
        //         // Open the channel
        //         let channelId = try await BitcoinManager.shared.connectOpenChannel(
        //             nodeId: nodeId,
        //             address: address,
        //             channelAmountSats: channelAmountSats,
        //             pushToCounterpartyMsat: pushAmountSats,
        //             channelConfig: nil,
        //             announceChannel: true
        //         )
                
        //         print("[TEMP] Channel opened successfully! Channel ID: \(channelId)")
                
        //         DispatchQueue.main.async {
        //             self.showAlert(
        //                 presentingController: self,
        //                 title: "Channel Opened",
        //                 message: "Successfully opened channel to \(nodeId) with \(channelAmountSats) sats (pushed \(pushAmountSats) sats)",
        //                 buttons: ["OK"],
        //                 actions: nil
        //             )
        //         }
                
        //     } catch {
        //         print("[TEMP] Error opening channel: \(error)")
        //         DispatchQueue.main.async {
        //             self.showAlert(
        //                 presentingController: self,
        //                 title: "Channel Open Failed",
        //                 message: "Failed to open channel: \(error.localizedDescription)",
        //                 buttons: ["OK"],
        //                 actions: nil
        //             )
        //         }
        //     }
        // }
        
        self.coreVC!.launchQuestion(question: Language.getWord(withID: "lightningchannels"), answer: Language.getWord(withID: "lightningexplanation1"), type: "lightningexplanation")
    }
    
    @objc func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.subheaderLabel.textColor = Colors.getColor("blackorwhite")
        self.addHeader(iconLight: "iconpiggywhite", iconDark: "iconpiggyyellow", title: Language.getWord(withID: "devicedetails2"))
        self.deviceTableView.reloadData()
    }
    
    @objc func setWords() {
        
        self.subheaderLabel.text = Language.getWord(withID: "accessdetails")
    }
    
}

extension UIViewController {
    
    func darkModeIsOn() -> Bool {
        switch CacheManager.darkMode() {
        case .light:
            return false
        case .dark:
            return true
        case .device:
            if self.traitCollection.userInterfaceStyle == .dark {
                return true
            } else {
                return false
            }
        }
    }
}

