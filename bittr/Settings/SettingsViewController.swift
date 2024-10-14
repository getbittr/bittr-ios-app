//
//  SettingsViewController.swift
//  bittr
//
//  Created by Tom Melters on 21/04/2023.
//

import UIKit

class SettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    // UI elements
    @IBOutlet weak var settingsTableView: UITableView!
    @IBOutlet weak var settingsTableViewHeight: NSLayoutConstraint!
    @IBOutlet weak var appVersion: UILabel!
    
    // Variables
    var coreVC:CoreViewController?
    var tappedUrl:String?
    let settings = [["label":"getsupport", "icon":"envelope", "id":"support"],["label":"restorewallet", "icon":"banknote", "id":"restore"],["label":"privacypolicy", "icon":"checkmark.shield", "id":"privacy"],["label":"termsandconditions", "icon":"book.pages", "id":"terms"],["label":"currency", "icon":"dollarsign.circle", "id":"currency"],["label":"walletandbalance", "icon":"bitcoinsign.circle", "id":"wallets"],["label":"devicedetails", "icon":"ipad.and.iphone", "id":"device"]]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.setWords()
        
        // Table view
        settingsTableView.delegate = self
        settingsTableView.dataSource = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        self.changeColors()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        settingsTableViewHeight.constant = CGFloat(settings.count * 60)
        
        return settings.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath) as? SettingsTableViewCell
        
        if let actualCell = cell {
            
            actualCell.layer.zPosition = CGFloat(indexPath.row)
            actualCell.settingsCardImage.image = UIImage(systemName: self.settings[indexPath.row]["icon"] ?? "bitcoinsign.circle")
            actualCell.settingsCardImage.tintColor = UIColor(red: 248/255, green: 199/255, blue: 68/255, alpha: 1)
            actualCell.settingsCardLabel.text = Language.getWord(withID: self.settings[indexPath.row]["label"] ?? "Unnamed")
            actualCell.settingsButton.accessibilityIdentifier = self.settings[indexPath.row]["id"] ?? ""
            
            if self.settings[indexPath.row]["id"] == "currency" {
                actualCell.currencyLabel.text = "€"
                if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                    actualCell.currencyLabel.text = "CHF"
                }
            } else {
                actualCell.currencyLabel.text = ""
            }
            
            return actualCell
        }
        
        return UITableViewCell()
    }
    
    @IBAction func settingsTapped(_ sender: UIButton) {
        
        if sender.accessibilityIdentifier == "privacy" {
            self.tappedUrl = "https://getbittr.com/privacy-policy"
            self.performSegue(withIdentifier: "SettingsToWebsite", sender: self)
        } else if sender.accessibilityIdentifier == "terms" {
            self.tappedUrl = "https://getbittr.com/terms-and-conditions"
            self.performSegue(withIdentifier: "SettingsToWebsite", sender: self)
        } else if sender.accessibilityIdentifier == "support" {
            self.tappedUrl = "https://getbittr.com/support"
            self.performSegue(withIdentifier: "SettingsToWebsite", sender: self)
        } else if sender.accessibilityIdentifier == "restore" {
            
            let alert = UIAlertController(title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "restorewallet2"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "restore"), style: .destructive, handler: {_ in
                
                let secondAlert = UIAlertController(title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "restorewallet3"), preferredStyle: .alert)
                secondAlert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
                secondAlert.addAction(UIAlertAction(title: Language.getWord(withID: "restore"), style: .destructive, handler: {_ in
                    
                    if let actualCoreVC = self.coreVC {
                        actualCoreVC.resetApp(nodeIsRunning: true)
                    }
                }))
                self.present(secondAlert, animated: true)
            }))
            self.present(alert, animated: true)
        } else if sender.accessibilityIdentifier == "currency" {
            let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            let eurOption = UIAlertAction(title: "EUR €", style: .default) { (action) in
                
                UserDefaults.standard.set("€", forKey: "currency")
                let notificationDict:[String: Any] = ["currency":"€"]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecurrency"), object: nil, userInfo: notificationDict) as Notification)
            }
            let chfOption = UIAlertAction(title: "CHF", style: .default) { (action) in
                
                UserDefaults.standard.set("CHF", forKey: "currency")
                let notificationDict:[String: Any] = ["currency":"CHF"]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecurrency"), object: nil, userInfo: notificationDict) as Notification)
            }
            let cancelAction = UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil)
            actionSheet.addAction(eurOption)
            actionSheet.addAction(chfOption)
            actionSheet.addAction(cancelAction)
            present(actionSheet, animated: true, completion: nil)
        } else if sender.accessibilityIdentifier == "wallets" {
            if let actualCoreVC = self.coreVC {
                if actualCoreVC.walletHasSynced == false {
                    // Wallet isn't ready.
                    let alert = UIAlertController(title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
                    self.present(alert, animated: true)
                    return
                }
            }
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "openmovevc"), object: nil, userInfo: nil) as Notification)
        } else if sender.accessibilityIdentifier == "device" {
            self.performSegue(withIdentifier: "SettingsToDevice", sender: self)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "SettingsToWebsite" {
            
            let websiteVC = segue.destination as? WebsiteViewController
            if let actualWebsiteVC = websiteVC {
                if let actualTappedUrl = self.tappedUrl {
                    
                    actualWebsiteVC.tappedUrl = actualTappedUrl
                }
            }
        } else if segue.identifier == "SettingsToDevice" {
            if let deviceVC = segue.destination as? DeviceViewController {
                if let actualCoreVC = self.coreVC {
                    if let actualHomeVC = actualCoreVC.homeVC {
                        deviceVC.homeVC = actualHomeVC
                    }
                }
            }
        }
    }
    
    @objc func changeColors() {
        
        self.appVersion.textColor = Colors.getColor(color: "appversion")
    }
    
}
