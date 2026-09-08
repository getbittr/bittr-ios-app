//
//  DeviceViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/01/2024.
//

import UIKit
import LDKNode

class DeviceViewController: UIViewController, UNUserNotificationCenterDelegate, UITableViewDelegate, UITableViewDataSource {
    
    // Table view
    @IBOutlet weak var deviceTableView: UITableView!
    @IBOutlet weak var deviceTableViewHeight: NSLayoutConstraint!
    
    // Table items
    let deviceItems = [
        ["id":"darkmode", "label":Language.getWord(withID: "darkmode"), "button":"", "icon":"moon.fill"],
        ["id":"language", "label":Language.getWord(withID: "language"), "button":"", "icon":"globe.europe.africa.fill"],
        ["id":"currency", "label":Language.getWord(withID: "currency"), "button":"", "icon":"dollarsign.circle.fill"],
        ["id":"devicetoken", "label":Language.getWord(withID: "devicetoken"), "button":Language.getWord(withID: "fetch"), "icon":"iphone"],
        ["id":"publickey", "label":Language.getWord(withID: "publickey"), "button":Language.getWord(withID: "fetch"), "icon":"key.horizontal.fill"],
        ["id":"bittrpeer", "label":Language.getWord(withID: "bittrpeer"), "button":Language.getWord(withID: "check"), "icon":"point.topleft.down.to.point.bottomright.curvepath.fill"],
        ["id":"pendingpayouts", "label":Language.getWord(withID: "bittrpendingpayout"), "button":Language.getWord(withID: "check"), "icon":"hourglass"],
        ["id":"lightningchannels", "label":Language.getWord(withID: "lightningchannels2"), "button":"", "icon":"bolt.fill"],
        ["id":"restore", "label":Language.getWord(withID: "removewallet"), "button":"", "icon":"trash.fill"]
    ]
    
    // Header
    @IBOutlet weak var subheaderLabel: UILabel!
    
    // Other VCs
    var coreVC:CoreViewController?
    var homeVC:HomeViewController?
    var tappedCell:DeviceTableViewCell?
    var channelsCount:String?
    var pendingPayout:BittrPendingPayout?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Table view
        self.deviceTableView.delegate = self
        self.deviceTableView.dataSource = self
        self.deviceTableViewHeight.constant = CGFloat(self.deviceItems.count * 55)
        
        // Notifications
        NotificationCenter.default.addObserver(self, selector: #selector(showToken), name: NSNotification.Name(rawValue: "receivedToken"), object: nil)
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
            cell.cellButton.boundString = cellTag
            cell.cellButton.accessibilityIdentifier = "device.row.\(cellTag)"
            
            cell.hideDarkMode()
            switch cellTag {
            case "language":
                if CacheManager.getLanguage() == "en_US" {
                    cell.buttonLabel.text = "English"
                }
            case "currency":
                cell.buttonLabel.text = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue().chosenCurrency
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
        self.showAlert(title: Language.getWord(withID: "selectlanguage"), message: Language.getWord(withID: "selectlanguagemessage"), buttons: [.dismiss(Language.getWord(withID: "cancel")), .action("English (US)") { CacheManager.changeLanguage("en_US") }])
    }

    func changeCurrency() {
        self.showAlert(title: Language.getWord(withID: "selectcurrency"), message: Language.getWord(withID: "selectcurrencymessage"), buttons: [.dismiss(Language.getWord(withID: "cancel")), .action("EUR €") { self.selectCurrency("€") }, .action("CHF") { self.selectCurrency("CHF") }])
    }
    
    func selectCurrency(_ currency:String) {
        CacheStore.set(currency, for: CacheKeys.currency)
        self.coreVC?.homeVC?.changeCurrency()
        self.deviceTableView.reloadData()
    }

    @objc func showToken(notification:NSNotification) {
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let notificationToken = userInfo["token"] as? String {
                self.showAlert(title: Language.getWord(withID: "devicetoken"), message: "\(notificationToken)", buttons: [.action(Language.getWord(withID: "copy")) { UIPasteboard.general.string = notificationToken }, .dismiss(Language.getWord(withID: "close"))])
            }
        }
    }
    
    func getPublicKey() {
        if let lightningKey = BitcoinManager.shared.nodeId() {
            self.showAlert(title: Language.getWord(withID: "publickey"), message: "\(lightningKey)", buttons: [.action(Language.getWord(withID: "copy")) { UIPasteboard.general.string = BitcoinManager.shared.nodeId()! }, .dismiss(Language.getWord(withID: "close"))])
        } else {
            self.showAlert(title: Language.getWord(withID: "publickey"), message: Language.getWord(withID: "syncingwallet2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        }
    }
    
    func imagesButtonTapped() {
        self.showAlert(title: Language.getWord(withID: "cachedimages"), message: Language.getWord(withID: "cachedimages1"), buttons: [.action(Language.getWord(withID: "remove")) { self.emptyImageCache() }, .dismiss(Language.getWord(withID: "cancel"))])
    }
    
    func emptyImageCache() {
        CacheManager.emptyImage()
        self.showAlert(title: Language.getWord(withID: "cacheemptied"), message: Language.getWord(withID: "cachedimages2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
    }
    
    func checkPeerConnection() {
        
        self.tappedCell?.stopAnimating()
        
        if isConnectedToPeer() {
            self.showAlert(title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        } else {
            self.showAlert(title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer3"), buttons: [.dismiss(Language.getWord(withID: "close")), .action(Language.getWord(withID: "connect")) { self.reconnectToPeer() }])
        }
    }
    
    func reconnectToPeer() {
        
        self.tappedCell?.animateCell()
        
        Task {
            _ = await BitcoinManager.shared.didEstablishPeerConnection()
            self.checkPeerConnection()
        }
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
        //                 //                 title: "Channel Opened",
        //                 message: "Successfully opened channel to \(nodeId) with \(channelAmountSats) sats (pushed \(pushAmountSats) sats)",
        //                 buttons: ["OK"],
        //                 actions: nil
        //             )
        //         }
                
        //     } catch {
        //         print("[TEMP] Error opening channel: \(error)")
        //         DispatchQueue.main.async {
        //             self.showAlert(
        //                 //                 title: "Channel Open Failed",
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
    
    func checkPendingPayout() {
        
        let deviceVC = self as? DeviceViewController
        let coreVC = self as? CoreViewController
        deviceVC?.tappedCell?.animateCell()
        
        let lightningPubKey = BitcoinManager.shared.nodeId()!
        let timestamp = Int(Date().timeIntervalSince1970)
        
        Task {
            let lightningSignature:String
            do {
                lightningSignature = try await BitcoinManager.shared.signMessage(message: "notifications:\(lightningPubKey):\(timestamp)")
            } catch {
                Log.info("Could not sign message. \(error.localizedDescription)")
                return
            }
            
            await CallsManager.makeApiCall(url: "https://getbittr.com/api/notifications?timestamp=\(timestamp)&signature=\(lightningSignature)&pubkey=\(lightningPubKey)", parameters: nil, getOrPost: .get) { result in
                
                DispatchQueue.main.async {
                    deviceVC?.tappedCell?.stopAnimating()
                    deviceVC?.tappedCell = nil
                    
                    switch result {
                    case .success(let receivedDictionary):
                        Log.info("Successfully received notifications dictionary.")
                        
                        let receivedNotifications = receivedDictionary.toNotifications()
                        Log.debug("Received notifications: \(receivedNotifications.count)")
                        
                        guard let lastNotification = receivedNotifications.last, let amountMsat = lastNotification.transaction?["bitcoin_amount"] as? String else {
                            Log.info("No notifications received.")
                            if deviceVC != nil {
                                deviceVC!.showAlert(title: Language.getWord(withID: "bittrpendingpayout"), message: Language.getWord(withID: "bittrpendingpayout2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                            }
                            return
                        }
                        
                        Log.info("Payout available for handling.")
                        deviceVC?.pendingPayout = lastNotification
                        coreVC?.pendingPayout = lastNotification
                        self.showAlert(title: Language.getWord(withID: "bittrpendingpayout"), message: Language.getWord(withID: "bittrpendingpayout3"), buttons: [.dismiss(Language.getWord(withID: "cancel")), .action(Language.getWord(withID: "confirm")) { self.handlePendingPayout() }])
                    case .failure(let error):
                        Log.info("Did not receive notifications dictionary: \(error)")
                        if deviceVC != nil {
                            deviceVC!.showAlert(title: Language.getWord(withID: "bittrpendingpayout"), message: Language.getWord(withID: "bittrpendingpayout2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                        }
                    }
                }
            }
        }
    }
    
    func handlePendingPayout() {
        
        let deviceVC = self as? DeviceViewController
        let coreVC = self as? CoreViewController
        let pendingPayout = deviceVC?.pendingPayout ?? coreVC!.pendingPayout!
        
        // Create notification.
        let thisNotification = BittrNotification()
        thisNotification.id = UUID().uuidString
        thisNotification.date = Date()
        thisNotification.type = .lightningPayout
        thisNotification.notificationID = pendingPayout.id!
        thisNotification.amountMsat = (pendingPayout.transaction!["bitcoin_amount"] as! String).toNumber().inSatoshis() * 1000
        
        // Cache notification.
        CacheManager.cacheLastNotification(thisNotification)
        
        // Handle notification payout.
        (deviceVC?.coreVC ?? coreVC!).wasNotified = true
        (deviceVC?.coreVC ?? coreVC!).handlePayoutNotification(thisNotification)
        
        // Dismiss DeviceVC.
        coreVC?.pendingPayout = nil
        deviceVC?.dismiss(animated: true)
    }
}

extension NSDictionary {
    
    func toNotifications() -> [BittrPendingPayout] {
        
        if let data = self["data"] as? [NSDictionary] {
            
            var pendingPayouts = [BittrPendingPayout]()
            
            for eachDictionary in data {
                guard
                    let insertedAt = eachDictionary["inserted_at"] as? String,
                    let sentAt = eachDictionary["sent_at"] as? String,
                    let status = eachDictionary["status"] as? String,
                    let notificationType = eachDictionary["notification_type"] as? String,
                    let attemptsCount = eachDictionary["attempts_count"] as? Int,
                    let id = eachDictionary["id"] as? String,
                    let lastAttemptAt = eachDictionary["last_attempt_at"] as? String,
                    let transaction = eachDictionary["transaction"] as? NSDictionary
                else {
                    break
                }
                
                let thisPendingPayout = BittrPendingPayout()
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                
                thisPendingPayout.insertedAt = dateFormatter.date(from: insertedAt)
                thisPendingPayout.sentAt = dateFormatter.date(from: sentAt)
                thisPendingPayout.lastAttemptAt = dateFormatter.date(from: lastAttemptAt)
                thisPendingPayout.status = status
                thisPendingPayout.notificationType = notificationType
                thisPendingPayout.attemptsCount = attemptsCount
                thisPendingPayout.id = id
                thisPendingPayout.transaction = transaction
                
                if thisPendingPayout.notificationType == "payout", thisPendingPayout.status == "sent" {
                    pendingPayouts += [thisPendingPayout]
                }
            }
            
            pendingPayouts.sort { payout1, payout2 in
                payout2.lastAttemptAt! > payout1.lastAttemptAt!
            }
            
            return pendingPayouts
        } else {
            return []
        }
    }
}

class BittrPendingPayout: NSObject {
    var attemptsCount:Int?
    var id:String?
    var insertedAt:Date?
    var lastAttemptAt:Date?
    var lightningInvoice:String?
    var notificationType:String?
    var sentAt:Date?
    var status:String?
    var transaction:NSDictionary?
}
