//
//  SettingsViewController.swift
//  bittr
//
//  Created by Tom Melters on 21/04/2023.
//

import UIKit
import LDKNode
import Sentry

class SettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    // UI elements
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var settingsTableView: UITableView!
    @IBOutlet weak var settingsTableViewHeight: NSLayoutConstraint!
    @IBOutlet weak var appVersion: UILabel!
    
    // Variables
    var coreVC:CoreViewController?
    var tappedUrl:String?
    let settings = [
        ["label":"getsupport", "icon":"envelope.fill", "id":"support"],
        ["label":"privacypolicy", "icon":"checkmark.shield.fill", "id":"privacy"],
        ["label":"termsandconditions", "icon":"book.pages.fill", "id":"terms"],
        ["label":"devicedetails", "icon":"ipad.and.iphone", "id":"device"]
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.setWords()
        self.changeColors()
        
        // Table view
        self.settingsTableView.delegate = self
        self.settingsTableView.dataSource = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        self.settingsTableViewHeight.constant = CGFloat(settings.count * 55)
        
        return settings.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 55
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath) as? SettingsTableViewCell {
            
            cell.layer.zPosition = CGFloat(indexPath.row)
            cell.settingsCardImage.image = UIImage(systemName: self.settings[indexPath.row]["icon"] ?? "bitcoinsign.circle")
            cell.settingsCardImage.tintColor = UIColor(red: 248/255, green: 199/255, blue: 68/255, alpha: 1)
            cell.settingsCardLabel.text = Language.getWord(withID: self.settings[indexPath.row]["label"] ?? "Unnamed")
            let rowId = self.settings[indexPath.row]["id"] ?? ""
            cell.settingsButton.boundString = rowId
            cell.settingsButton.accessibilityIdentifier = "settings.row.\(rowId)"

            return cell
        } else {
            return UITableViewCell()
        }
    }
    
    @IBAction func settingsTapped(_ sender: UIButton) {
        
        if sender.boundString == "privacy" {
            self.tappedUrl = "https://getbittr.com/privacy-policy"
            self.performSegue(withIdentifier: "SettingsToWebsite", sender: self)
        } else if sender.boundString == "terms" {
            self.tappedUrl = "https://getbittr.com/terms-and-conditions"
            self.performSegue(withIdentifier: "SettingsToWebsite", sender: self)
        } else if sender.boundString == "support" {
            self.tappedUrl = "https://getbittr.com/support"
            self.performSegue(withIdentifier: "SettingsToWebsite", sender: self)
        } else if sender.boundString == "device" {
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
                    deviceVC.coreVC = actualCoreVC
                    if let actualHomeVC = actualCoreVC.homeVC {
                        deviceVC.homeVC = actualHomeVC
                    }
                }
            }
        }
    }
    
}
