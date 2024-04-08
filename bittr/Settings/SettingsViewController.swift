//
//  SettingsViewController.swift
//  bittr
//
//  Created by Tom Melters on 21/04/2023.
//

import UIKit

class SettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak var settingsTableView: UITableView!
    @IBOutlet weak var settingsTableViewHeight: NSLayoutConstraint!
    
    var coreVC:CoreViewController?
    var tappedUrl:String?
    
    let settings = [/*["label":"Share feedback", "icon":"iconfeedback", "id":"feedback"],*/["label":"Get support", "icon":"envelope", "id":"support"],["label":"Restore wallet", "icon":"banknote", "id":"restore"],["label":"Privacy Policy", "icon":"checkmark.shield", "id":"privacy"],["label":"Terms & Conditions", "icon":"book.pages", "id":"terms"],["label":"Currency", "icon":"dollarsign.circle", "id":"currency"],["label":"Wallet details", "icon":"bitcoinsign.circle", "id":"wallets"],["label":"Device details", "icon":"ipad.and.iphone", "id":"device"]]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        settingsTableView.delegate = self
        settingsTableView.dataSource = self
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        settingsTableViewHeight.constant = CGFloat(settings.count * 60)
        
        return settings.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath) as? SettingsTableViewCell
        
        if let actualCell = cell {
            
            actualCell.layer.zPosition = CGFloat(indexPath.row)
            //actualCell.settingsCardImage.image = UIImage(named: self.settings[indexPath.row]["icon"] ?? "iconterms")
            actualCell.settingsCardImage.image = UIImage(systemName: self.settings[indexPath.row]["icon"] ?? "bitcoinsign.circle")
            actualCell.settingsCardImage.tintColor = UIColor(red: 248/255, green: 199/255, blue: 68/255, alpha: 1)
            actualCell.settingsCardLabel.text = self.settings[indexPath.row]["label"] ?? "Unnamed"
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
            
            /*let website:String = "https://getbittr.com/privacy-policy"
            let websiteUrl:NSURL? = NSURL(string: website)
            if websiteUrl != nil {
                UIApplication.shared.open(websiteUrl! as URL, options: [:], completionHandler: nil)
            }*/
        } else if sender.accessibilityIdentifier == "terms" {
            self.tappedUrl = "https://getbittr.com/terms-and-conditions"
            self.performSegue(withIdentifier: "SettingsToWebsite", sender: self)
            
            /*let website:String = "https://getbittr.com/terms-and-conditions"
            let websiteUrl:NSURL? = NSURL(string: website)
            if websiteUrl != nil {
                UIApplication.shared.open(websiteUrl! as URL, options: [:], completionHandler: nil)
            }*/
        } else if sender.accessibilityIdentifier == "support" {
            self.tappedUrl = "https://getbittr.com/support"
            self.performSegue(withIdentifier: "SettingsToWebsite", sender: self)
            
            /*let website:String = "https://getbittr.com/support"
            let websiteUrl:NSURL? = NSURL(string: website)
            if websiteUrl != nil {
                UIApplication.shared.open(websiteUrl! as URL, options: [:], completionHandler: nil)
            }*/
        } else if sender.accessibilityIdentifier == "restore" {
            
            let alert = UIAlertController(title: "Restore wallet", message: "\nThis app only supports one wallet simultaneously. Restoring a wallet means removing this current wallet from your device.\n\nOnly restore a wallet if you're sure you've properly backed up this current wallet.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Restore", style: .destructive, handler: {_ in
                
                let secondAlert = UIAlertController(title: "Restore wallet", message: "\nAre you sure you want to remove this current wallet from your device and replace it with a restored one?\n\nIf you tap Restore, we'll reset and close the app. Please reopen it to proceed with your restoration.", preferredStyle: .alert)
                secondAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                secondAlert.addAction(UIAlertAction(title: "Restore", style: .destructive, handler: {_ in
                    
                    if let actualCoreVC = self.coreVC {
                        actualCoreVC.resetApp()
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
            /*let usdOption = UIAlertAction(title: "USD $", style: .default) { (action) in
                let notificationDict:[String: Any] = ["currency":"$"]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecurrency"), object: nil, userInfo: notificationDict) as Notification)
            }*/
            let chfOption = UIAlertAction(title: "CHF", style: .default) { (action) in
                
                UserDefaults.standard.set("CHF", forKey: "currency")
                let notificationDict:[String: Any] = ["currency":"CHF"]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecurrency"), object: nil, userInfo: notificationDict) as Notification)
            }
            /*let gbpOption = UIAlertAction(title: "GBP £", style: .default) { (action) in
                let notificationDict:[String: Any] = ["currency":"£"]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecurrency"), object: nil, userInfo: notificationDict) as Notification)
            }*/
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            actionSheet.addAction(eurOption)
            //actionSheet.addAction(usdOption)
            actionSheet.addAction(chfOption)
            //actionSheet.addAction(gbpOption)
            actionSheet.addAction(cancelAction)
            present(actionSheet, animated: true, completion: nil)
        } else if sender.accessibilityIdentifier == "wallets" {
            if let actualCoreVC = self.coreVC {
                if actualCoreVC.walletHasSynced == false {
                    // Wallet isn't ready.
                    let alert = UIAlertController(title: "Syncing wallet", message: "Please wait a moment while we're syncing your wallet.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
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
        }
    }
    
}
