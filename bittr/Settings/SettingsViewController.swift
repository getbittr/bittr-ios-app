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
    
    let settings = [["label":"Privacy Policy", "icon":"iconprivacy", "id":"privacy"],["label":"Terms & Conditions", "icon":"iconterms", "id":"terms"],["label":"Share feedback", "icon":"iconfeedback", "id":"feedback"],["label":"Get support", "icon":"iconsupport", "id":"support"],["label":"Currency", "icon":"iconcurrency", "id":"currency"]]
    
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
            actualCell.settingsCardImage.image = UIImage(named: self.settings[indexPath.row]["icon"] ?? "iconterms")
            actualCell.settingsCardLabel.text = self.settings[indexPath.row]["label"] ?? "Unnamed"
            actualCell.settingsButton.accessibilityIdentifier = self.settings[indexPath.row]["id"] ?? ""
            
            if self.settings[indexPath.row]["id"] == "currency" {
                actualCell.currencyLabel.text = "€"
            } else {
                actualCell.currencyLabel.text = ""
            }
            
            return actualCell
        }
        
        return UITableViewCell()
    }
    
    @IBAction func settingsTapped(_ sender: UIButton) {
        
        if sender.accessibilityIdentifier == "privacy" {
            let website:String = "https://getbittr.com/privacy-policy"
            let websiteUrl:NSURL? = NSURL(string: website)
            if websiteUrl != nil {
                UIApplication.shared.open(websiteUrl! as URL, options: [:], completionHandler: nil)
            }
        } else if sender.accessibilityIdentifier == "terms" {
            let website:String = "https://getbittr.com/terms-and-conditions"
            let websiteUrl:NSURL? = NSURL(string: website)
            if websiteUrl != nil {
                UIApplication.shared.open(websiteUrl! as URL, options: [:], completionHandler: nil)
            }
        } else if sender.accessibilityIdentifier == "support" {
            let website:String = "https://getbittr.com/support"
            let websiteUrl:NSURL? = NSURL(string: website)
            if websiteUrl != nil {
                UIApplication.shared.open(websiteUrl! as URL, options: [:], completionHandler: nil)
            }
        } else if sender.accessibilityIdentifier == "currency" {
            let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            let eurOption = UIAlertAction(title: "EUR €", style: .default) { (action) in
                let notificationDict:[String: Any] = ["currency":"€"]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecurrency"), object: nil, userInfo: notificationDict) as Notification)
            }
            let usdOption = UIAlertAction(title: "USD $", style: .default) { (action) in
                let notificationDict:[String: Any] = ["currency":"$"]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecurrency"), object: nil, userInfo: notificationDict) as Notification)
            }
            let chfOption = UIAlertAction(title: "CHF", style: .default) { (action) in
                let notificationDict:[String: Any] = ["currency":"CHF"]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecurrency"), object: nil, userInfo: notificationDict) as Notification)
            }
            let gbpOption = UIAlertAction(title: "GBP £", style: .default) { (action) in
                let notificationDict:[String: Any] = ["currency":"£"]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecurrency"), object: nil, userInfo: notificationDict) as Notification)
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            actionSheet.addAction(eurOption)
            actionSheet.addAction(usdOption)
            actionSheet.addAction(chfOption)
            actionSheet.addAction(gbpOption)
            actionSheet.addAction(cancelAction)
            present(actionSheet, animated: true, completion: nil)
        }
    }
    
}
