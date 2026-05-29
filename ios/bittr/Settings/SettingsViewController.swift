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
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        self.changeColors()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        settingsTableViewHeight.constant = CGFloat(settings.count * 60)
        
        return settings.count
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
            
            if self.settings[indexPath.row]["id"] == "currency" {
                cell.currencyLabel.text = self.getCorrectBitcoinValue(coreVC: self.coreVC!).chosenCurrency
            } else {
                cell.currencyLabel.text = ""
            }
            
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
        } else if sender.boundString == "restore" {
            self.coreVC?.restoreWalletTapped()
        } else if sender.boundString == "currency" {
            let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            let eurOption = UIAlertAction(title: "EUR €", style: .default) { (action) in
                
                UserDefaults.standard.set("€", forKey: "currency")
                self.coreVC?.homeVC?.changeCurrency()
                self.settingsTableView.reloadData()
            }
            let chfOption = UIAlertAction(title: "CHF", style: .default) { (action) in
                
                UserDefaults.standard.set("CHF", forKey: "currency")
                self.coreVC?.homeVC?.changeCurrency()
                self.settingsTableView.reloadData()
            }
            let cancelAction = UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil)
            actionSheet.addAction(eurOption)
            actionSheet.addAction(chfOption)
            actionSheet.addAction(cancelAction)
            present(actionSheet, animated: true, completion: nil)
        } else if sender.boundString == "wallets" {
            if self.coreVC != nil, !self.coreVC!.walletHasSynced {
                // Wallet isn't ready.
                self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                return
            }
            self.coreVC?.homeVC?.moveButtonTapped()
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
