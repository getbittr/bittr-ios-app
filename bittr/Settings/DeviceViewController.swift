//
//  DeviceViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/01/2024.
//

import UIKit

class DeviceViewController: UIViewController, UNUserNotificationCenterDelegate {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var tokenView: UIView!
    @IBOutlet weak var keyView: UIView!
    @IBOutlet weak var tokenButton: UIButton!
    @IBOutlet weak var keyButton: UIButton!
    @IBOutlet weak var imagesView: UIView!
    @IBOutlet weak var imagesButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        tokenButton.setTitle("", for: .normal)
        keyButton.setTitle("", for: .normal)
        imagesButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        tokenView.layer.cornerRadius = 13
        keyView.layer.cornerRadius = 13
        imagesView.layer.cornerRadius = 13
        
        NotificationCenter.default.addObserver(self, selector: #selector(showToken), name: NSNotification.Name(rawValue: "showtoken"), object: nil)
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
                alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil))
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
        alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @IBAction func imagesButtonTapped(_ sender: UIButton) {
        
        let alert = UIAlertController(title: "Cached images", message: "Are you sure you want to remove your cached images?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Remove", style: .default, handler: { _ in
            // Copy the invoice to the clipboard
            CacheManager.emptyImage()
            let alert = UIAlertController(title: "Cache emptied", message: "Any cached images have been removed.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
}
