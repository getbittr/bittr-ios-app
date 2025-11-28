//
//  BuyViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit
import Sentry

class BuyViewController: UIViewController, UITextFieldDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    // General
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var ibanCollectionView: UICollectionView!
    
    // Update data
    @IBOutlet weak var updateDataView: UIView!
    @IBOutlet weak var updateDataLabel: UILabel!
    @IBOutlet weak var resetIcon: UIImageView!
    @IBOutlet weak var updateDataButton: UIButton!
    @IBOutlet weak var updateDataSpinner: UIActivityIndicatorView!
    
    // No deposit codes
    @IBOutlet weak var emptyView: UIView!
    @IBOutlet weak var emptyLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var continueView: UIView!
    @IBOutlet weak var continueButton: UIButton!
    @IBOutlet weak var centerViewBottom: NSLayoutConstraint!
    
    // Client details
    var allIbanEntities = [IbanEntity]()
    
    // Articles
    var coreVC:CoreViewController?
    var registerIbanVC:RegisterIbanViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii and button titles.
        self.continueView.layer.cornerRadius = 13
        self.continueButton.setTitle("", for: .normal)
        self.downButton.setTitle("", for: .normal)
        self.updateDataButton.setTitle("", for: .normal)
        
        // Collection view.
        self.ibanCollectionView.delegate = self
        self.ibanCollectionView.dataSource = self
        self.ibanCollectionView.contentInset = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        
        // Set colors and language.
        self.changeColors()
        self.setWords()
        
        // Parse IBAN entities.
        self.parseIbanEntities()
    }
    
    func parseIbanEntities() {
        
        // Set IBAN entities.
        self.allIbanEntities = [IbanEntity]()
        if self.coreVC == nil {return}
        for eachIbanEntity in self.coreVC!.bittrWallet.ibanEntities {
            if eachIbanEntity.yourUniqueCode != "" {
                self.allIbanEntities += [eachIbanEntity]
            }
        }
        
        // Reload collection view.
        self.ibanCollectionView.reloadData()
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func saveButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "IbanCell", for: indexPath) as? IbanCollectionViewCell {
            
            if self.allIbanEntities.count == 0 { return cell }
            
            cell.cardBackgroundViewWidth.constant = self.view.bounds.width - 30
            
            cell.labelYourEmail.text = self.allIbanEntities[indexPath.row].yourEmail
            cell.labelYourIban.text = self.allIbanEntities[indexPath.row].yourIbanNumber
            cell.labelOurIban.text = self.allIbanEntities[indexPath.row].ourIbanNumber
            cell.labelOurName.text = self.allIbanEntities[indexPath.row].ourName
            cell.labelYourCode.text = self.allIbanEntities[indexPath.row].yourUniqueCode
            
            cell.ibanButton.accessibilityIdentifier = self.allIbanEntities[indexPath.row].ourIbanNumber
            cell.nameButton.accessibilityIdentifier = self.allIbanEntities[indexPath.row].ourName
            cell.codeButton.accessibilityIdentifier = self.allIbanEntities[indexPath.row].yourUniqueCode
            
            return cell
        } else {
            return UICollectionViewCell()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        if self.allIbanEntities.count > 0 {
            // There are deposit codes.
            self.emptyView.alpha = 0
            self.ibanCollectionView.alpha = 1
            self.updateDataView.alpha = 1
            NSLayoutConstraint.deactivate([self.centerViewBottom])
            self.centerViewBottom = NSLayoutConstraint(item: self.centerView, attribute: .bottom, relatedBy: .equal, toItem: self.updateDataView, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.centerViewBottom])
            self.view.layoutIfNeeded()
            
            return self.allIbanEntities.count
        } else {
            // There are no deposit codes.
            self.emptyView.alpha = 1
            self.ibanCollectionView.alpha = 0
            self.updateDataView.alpha = 0
            NSLayoutConstraint.deactivate([self.centerViewBottom])
            self.centerViewBottom = NSLayoutConstraint(item: self.centerView, attribute: .bottom, relatedBy: .equal, toItem: self.emptyView, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.centerViewBottom])
            self.view.layoutIfNeeded()
            
            return 0
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        let viewWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
        let cellWidth = viewWidth - 30
        return CGSize(width: cellWidth, height: 285)
    }
    
    @IBAction func continueButtonTapped(_ sender: UIButton) {
        self.performSegue(withIdentifier: "BuyToRegister", sender: self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "BuyToRegister" {
            if let registerVC = segue.destination as? RegisterIbanViewController {
                registerVC.coreVC = self.coreVC
                self.registerIbanVC = registerVC
            }
        }
    }

    @IBAction func copyItem(_ sender: UIButton) {
        
        UIPasteboard.general.string = sender.accessibilityIdentifier
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: sender.accessibilityIdentifier ?? "", buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func updateDataTapped(_ sender: UIButton) {
        self.getDepositCodeData()
    }
    
    func getDepositCodeData() {
        
        // Gather deposit codes.
        var depositCodes = [String]()
        for eachIbanEntity in self.allIbanEntities {
            depositCodes += [eachIbanEntity.yourUniqueCode]
        }
        if depositCodes.count == 0 { return }
        let depositCodesString = depositCodes.joined(separator: ",")
        
        // If LDK Node has not been started, we cannot sign the message or get the node ID.
        if LightningNodeService.shared.ldkNode == nil {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "buyvcupdatedetails"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        self.updateDataSpinner.startAnimating()
        Task {
            do {
                // Gather parameters.
                let lightningSignature = try await LightningNodeService.shared.signMessage(message: depositCodesString)
                let lightningPubKey = LightningNodeService.shared.nodeId()
                
                let envUrl = "\(EnvironmentConfig.bittrAPIBaseURL)/deposit_code_info?deposit_codes=\(depositCodesString)&signature=\(lightningSignature)&pubkey=\(lightningPubKey)"
                
                // Make API call.
                await CallsManager.makeApiCall(url: envUrl, parameters: nil, getOrPost: .get) { result in
                    
                    DispatchQueue.main.async {
                        self.updateDataSpinner.stopAnimating()
                    }
                    
                    switch result {
                    case .success(let receivedDictionary):
                        self.parseNewData(receivedDictionary: receivedDictionary)
                    case .failure(let error):
                        print("185 Error. \(error.localizedDescription)")
                        let errorMessage:String = {
                            switch error {
                            case .invalidURL: return "We could not reach our server."
                            case .requestFailed(let errorMessage): return errorMessage
                            case .decodingFailed: return "We couldn't decode the data we received from our server."
                            }
                        }()
                        DispatchQueue.main.async {
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "buyvcupdatedetails"), message: Language.getWord(withID: "buyvcupdatedetails4") + " \(errorMessage)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                        }
                    }
                }
            } catch {
                print("185 Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.updateDataSpinner.stopAnimating()
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "BuyViewController row 188", key: "context")
                    }
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "buyvcupdatedetails"), message: Language.getWord(withID: "buyvcupdatedetails4") + " Something went wrong creating a unique signature.", buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            }
        }
    }
    
    func parseNewData(receivedDictionary:NSDictionary) {
        
        if let receivedEntities = receivedDictionary["data"] as? [NSDictionary] {
            // Entities received in expected format.
            var someDetailsHaveChanged = false
            
            for eachEntity in receivedEntities {
                if
                    let depositCode = eachEntity["deposit_code"] as? String,
                    let partnerIban = eachEntity["iban"] as? String,
                    let partnerSwift = eachEntity["swift"] as? String {
                    
                    for (index, eachExistingEntity) in self.allIbanEntities.enumerated() {
                        if eachExistingEntity.yourUniqueCode == depositCode {
                            if partnerIban != eachExistingEntity.ourIbanNumber || partnerSwift != eachExistingEntity.ourSwift {
                                // Details have changed.
                                someDetailsHaveChanged = true
                                
                                // Update details in BuyVC.
                                self.allIbanEntities[index].ourIbanNumber = partnerIban
                                self.allIbanEntities[index].ourSwift = partnerSwift
                                self.allIbanEntities[index].lightningAddressUsername = (eachEntity["lightning_address_username"] as? String) ?? self.allIbanEntities[index].lightningAddressUsername
                                
                                // Update details in CoreVC.
                                for (walletIndex, eachWalletEntity) in self.coreVC!.bittrWallet.ibanEntities.enumerated() {
                                    if eachWalletEntity.yourUniqueCode == depositCode {
                                        self.coreVC!.bittrWallet.ibanEntities[walletIndex].ourIbanNumber = partnerIban
                                        self.coreVC!.bittrWallet.ibanEntities[walletIndex].ourSwift = partnerSwift
                                        self.coreVC!.bittrWallet.ibanEntities[walletIndex].lightningAddressUsername = (eachEntity["lightning_address_username"] as? String) ?? self.coreVC!.bittrWallet.ibanEntities[walletIndex].lightningAddressUsername
                                    }
                                }
                                
                                // Update details in cache.
                                CacheManager.addBittrIban(ibanID: eachExistingEntity.id, ourIban: partnerIban, ourSwift: partnerSwift, yourCode: depositCode, lightningAddressUsername: eachEntity["lightning_address_username"] as? String)
                            }
                        }
                    }
                }
            }
            
            if someDetailsHaveChanged {
                // Data has been updated.
                self.ibanCollectionView.reloadData()
                self.showAlert(presentingController: self, title: Language.getWord(withID: "buyvcupdatedetails"), message: Language.getWord(withID: "buyvcupdatedetails2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            } else {
                // Data was already up-to-date.
                self.showAlert(presentingController: self, title: Language.getWord(withID: "buyvcupdatedetails"), message: Language.getWord(withID: "buyvcupdatedetails3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        } else {
            // Data received in wrong format.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "buyvcupdatedetails"), message: Language.getWord(withID: "buyvcupdatedetails4") + " The data we received isn't in the expected format.", buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.subtitleLabel.textColor = Colors.getColor("blackorwhite")
        self.emptyLabel.textColor = Colors.getColor("blackorwhite")
        self.updateDataLabel.textColor = Colors.getColor("blackorwhite")
        self.updateDataSpinner.color = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.resetIcon.image = UIImage(named: "iconresetwhite")
        } else {
            self.resetIcon.image = UIImage(named: "iconreset")
        }
    }
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "buybitcoin")
        self.subtitleLabel.text = Language.getWord(withID: "buysubtitle")
        self.emptyLabel.text = Language.getWord(withID: "buyempty")
        self.updateDataLabel.text = Language.getWord(withID: "buyvcupdatedetails")
    }
}
