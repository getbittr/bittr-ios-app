//
//  UIViewController.swift
//  bittr
//
//  Created by Tom Melters on 1/13/26.
//

import UIKit

extension UIViewController {
    
    func checkInternetConnection() -> Bool {
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return false
        } else {
            return true
        }
    }
    
    func addHeader(iconLight:String, iconDark:String, title:String) {
        
        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .clear
        headerView.clipsToBounds = false
        headerView.layer.zPosition = 100
        self.view.addSubview(headerView)
        
        let headerViewTop = NSLayoutConstraint(item: headerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
        let headerViewLeft = NSLayoutConstraint(item: headerView, attribute: .leading, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
        let headerViewRight = NSLayoutConstraint(item: headerView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
        let headerViewHeight = NSLayoutConstraint(item: headerView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 58)
        self.view.addConstraints([headerViewTop, headerViewLeft, headerViewRight])
        headerView.addConstraint(headerViewHeight)
        
        let headerIcon = UIImageView()
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        if CacheManager.darkModeIsOn() {
            headerIcon.image = UIImage(named: iconDark)
        } else {
            headerIcon.image = UIImage(named: iconLight)
        }
        if headerIcon.image == nil {
            headerIcon.image = UIImage(systemName: iconLight)
            headerIcon.tintColor = Colors.getColor("whiteoryellow")
        }
        headerIcon.clipsToBounds = false
        headerIcon.contentMode = .scaleAspectFit
        headerView.addSubview(headerIcon)
        
        let headerIconHeight = NSLayoutConstraint(item: headerIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 18)
        let headerIconWidth = NSLayoutConstraint(item: headerIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 18)
        let headerIconCenterY = NSLayoutConstraint(item: headerIcon, attribute: .centerY, relatedBy: .equal, toItem: headerView, attribute: .centerY, multiplier: 1, constant: 0)
        let headerIconLeft = NSLayoutConstraint(item: headerIcon, attribute: .leading, relatedBy: .equal, toItem: headerView, attribute: .leading, multiplier: 1, constant: 20)
        headerIcon.addConstraints([headerIconHeight, headerIconWidth])
        headerView.addConstraints([headerIconLeft, headerIconCenterY])
        
        
        let headerLabel = UILabel()
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.clipsToBounds = false
        headerLabel.font = UIFont(name: "Gilroy-Bold", size: 18)
        headerLabel.textColor = Colors.getColor("whiteoryellow")
        headerLabel.text = title.lowercased()
        headerLabel.numberOfLines = 1
        headerLabel.textAlignment = .left
        headerLabel.lineBreakMode = .byTruncatingTail
        headerLabel.backgroundColor = .clear
        headerView.addSubview(headerLabel)
        
        let headerLabelLeft = NSLayoutConstraint(item: headerLabel, attribute: .leading, relatedBy: .equal, toItem: headerIcon, attribute: .trailing, multiplier: 1, constant: 10)
        let headerLabelCenterY = NSLayoutConstraint(item: headerLabel, attribute: .centerY, relatedBy: .equal, toItem: headerIcon, attribute: .centerY, multiplier: 1, constant: 1)
        let headerLabelHeight = NSLayoutConstraint(item: headerLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        let headerLabelWidth = NSLayoutConstraint(item: headerLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        headerLabel.addConstraints([headerLabelHeight, headerLabelWidth])
        headerView.addConstraints([headerLabelLeft, headerLabelCenterY])
        
        
        let downIcon = UIImageView()
        downIcon.translatesAutoresizingMaskIntoConstraints = false
        downIcon.clipsToBounds = false
        if CacheManager.darkModeIsOn() {
            downIcon.image = UIImage(named: "downarrow32yellow")
        } else {
            downIcon.image = UIImage(named: "downarrow32")
        }
        downIcon.contentMode = .scaleAspectFit
        headerView.addSubview(downIcon)
        
        let downIconHeight = NSLayoutConstraint(item: downIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 20)
        let downIconWidth = NSLayoutConstraint(item: downIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 20)
        let downIconCenterY = NSLayoutConstraint(item: downIcon, attribute: .centerY, relatedBy: .equal, toItem: headerIcon, attribute: .centerY, multiplier: 1, constant: 0)
        let downIconRight = NSLayoutConstraint(item: downIcon, attribute: .trailing, relatedBy: .equal, toItem: headerView, attribute: .trailing, multiplier: 1, constant: -20)
        downIcon.addConstraints([downIconHeight, downIconWidth])
        headerView.addConstraints([downIconRight, downIconCenterY])
        
        
        let downButton = UIButton()
        downButton.translatesAutoresizingMaskIntoConstraints = false
        downButton.isUserInteractionEnabled = true
        downButton.setTitle("", for: .normal)
        downButton.backgroundColor = .clear
        downButton.addTarget(self, action: #selector(self.dismissVC), for: .touchUpInside)
        downButton.layer.zPosition = 100
        downButton.accessibilityIdentifier = TestID.Header.downButton
        headerView.addSubview(downButton)
        
        let downButtonHeight = NSLayoutConstraint(item: downButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
        let downButtonWidth = NSLayoutConstraint(item: downButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
        let downButtonCenterX = NSLayoutConstraint(item: downButton, attribute: .centerX, relatedBy: .equal, toItem: downIcon, attribute: .centerX, multiplier: 1, constant: 0)
        let downButtonCenterY = NSLayoutConstraint(item: downButton, attribute: .centerY, relatedBy: .equal, toItem: downIcon, attribute: .centerY, multiplier: 1, constant: 0)
        downButton.addConstraints([downButtonHeight, downButtonWidth])
        headerView.addConstraints([downButtonCenterX, downButtonCenterY])
        
        self.view.layoutIfNeeded()
        
    }
    
    @objc func dismissVC() {
        self.view.endEditing(true)
        self.dismiss(animated: true)
    }
    
    @objc func askForPushNotifications() {
        self.hideAlert()

        let homeVC = self as? HomeViewController
        let swapVC = self as? SwapViewController
        let transfer15VC = self as? Transfer2ViewController
        let deviceVC = self as? DeviceViewController

        // UNUserNotificationCenter.getNotificationSettings fires its completion
        // on a background queue. Calling requestAuthorization off-main on newer
        // iOS / simulator versions silently fails to present the system prompt
        // (so Transfer2's Next-button spinner hangs forever waiting for
        // didRegisterForRemoteNotificationsWithDeviceToken that never fires).
        // Hop to main for the system-UI work; nest the inner completions too
        // since they're also delivered on a background queue.
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings { (settings) in
            DispatchQueue.main.async {

                switch settings.authorizationStatus {
                case .notDetermined:
                    // User hasn't set their preference yet — show system prompt.
                    current.delegate = (homeVC ?? swapVC ?? transfer15VC ?? deviceVC)
                    current.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                        Log.info("Permission granted: \(granted)")

                        DispatchQueue.main.async {
                            guard granted else {
                                transfer15VC?.checkPushNotificationStatus()
                                return
                            }

                            // Double check that the preference is now authorized.
                            current.getNotificationSettings { (updatedSettings) in
                                DispatchQueue.main.async {
                                    Log.info("Notification settings: \(updatedSettings)")
                                    guard updatedSettings.authorizationStatus == .authorized else {
                                        transfer15VC?.checkPushNotificationStatus()
                                        return
                                    }
                                    transfer15VC?.start2Fa = true
                                    UIApplication.shared.registerForRemoteNotifications()
                                }
                            }
                        }
                    }

                case .authorized, .provisional, .ephemeral:
                    // Already authorized in some form — register and let
                    // didRegisterForRemoteNotificationsWithDeviceToken trigger
                    // resume2Fa.
                    transfer15VC?.start2Fa = true
                    UIApplication.shared.registerForRemoteNotifications()

                case .denied:
                    // User previously denied notifications. Without them the
                    // 2FA flow can't continue, so stop the spinner instead of
                    // hanging silently.
                    transfer15VC?.cancelLoading()

                @unknown default:
                    transfer15VC?.cancelLoading()
                }
            }
        }
    }
    
    func getCorrectBitcoinValue(coreVC:CoreViewController) -> BitcoinValue {
        
        let bitcoinValue = BitcoinValue()
        bitcoinValue.currentValue = coreVC.bittrWallet.valueInEUR ?? 0.0
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            bitcoinValue.currentValue = coreVC.bittrWallet.valueInCHF ?? 0.0
            bitcoinValue.chosenCurrency = "CHF"
            bitcoinValue.apiUrl = "https://getbittr.com/api/price/btc/historical/chf"
        }
        
        return bitcoinValue
    }
    
}
