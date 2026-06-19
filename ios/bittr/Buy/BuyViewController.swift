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
    @IBOutlet weak var downIcon: UIImageView!
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var headerIcon: UIImageView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var ibanCollectionView: UICollectionView!
    
    // Update data
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
        
        // Collection view.
        self.ibanCollectionView.delegate = self
        self.ibanCollectionView.dataSource = self
        self.ibanCollectionView.contentInset = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        
        self.headerLabel.accessibilityIdentifier = TestID.Buy.headerLabel
        self.downButton.accessibilityIdentifier = TestID.Buy.downButton
        self.continueButton.accessibilityIdentifier = TestID.Buy.continueButton

        // Set colors and language.
        self.changeColors()
        self.setWords()
        
        // Parse IBAN entities.
        self.parseIbanEntities(uponPageLaunch: true)
    }
    
    func parseIbanEntities(uponPageLaunch:Bool) {
        
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
        
        if self.allIbanEntities.count > 0, uponPageLaunch {
            self.getDepositCodeData()
        }
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
            
            cell.ibanButton.boundString = self.allIbanEntities[indexPath.row].ourIbanNumber
            cell.nameButton.boundString = self.allIbanEntities[indexPath.row].ourName
            cell.codeButton.boundString = self.allIbanEntities[indexPath.row].yourUniqueCode

            // Payout-mode toggle for this deposit code.
            let entity = self.allIbanEntities[indexPath.row]
            cell.configurePaymentMode(entity.paymentMode)
            cell.onPaymentModeChange = { [weak self] newMode in
                self?.setPaymentMode(for: entity, newMode: newMode)
            }

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
            NSLayoutConstraint.deactivate([self.centerViewBottom])
            self.centerViewBottom = NSLayoutConstraint(item: self.centerView, attribute: .bottom, relatedBy: .equal, toItem: self.ibanCollectionView, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.centerViewBottom])
            self.view.layoutIfNeeded()
            
            return self.allIbanEntities.count
        } else {
            // There are no deposit codes.
            self.emptyView.alpha = 1
            self.ibanCollectionView.alpha = 0
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
        // Height was 285; raised to fit the payout-mode toggle added below the
        // deposit-code section. NOTE: verify the spacing visually in Xcode.
        return CGSize(width: cellWidth, height: 365)
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

        let value = sender.boundString ?? ""
        UIPasteboard.general.string = value
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: value, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    func getDepositCodeData() {
        
        // If LDK Node has not been started, we cannot sign the message or get the node ID.
        if BitcoinManager.shared.ldkNode == nil { return }
        
        // Gather parameters
        let lightningPubKey = BitcoinManager.shared.nodeId()!
        let timestamp = Int(Date().timeIntervalSince1970)
        let signature = "deposit_codes:\(lightningPubKey):\(timestamp)"
        
        // Start spinner
        self.updateDataSpinner.startAnimating()
        
        Task {
            // Delay the call 1 second to keep the spinner visible for a moment.
            try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
            
            let lightningSignature:String
            do {
                // Gather parameters.
                lightningSignature = try await BitcoinManager.shared.signMessage(message: signature)
            } catch {
                Log.info("185 Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.updateDataSpinner.stopAnimating()
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "BuyViewController row 203", key: "context")
                    }
                }
                return
            }
                
            let envUrl = "\(EnvironmentConfig.bittrAPIBaseURL)/deposit_code?timestamp=\(timestamp)&signature=\(lightningSignature)&pubkey=\(lightningPubKey)"
            
            // Make API call.
            await CallsManager.makeApiCall(url: envUrl, parameters: nil, getOrPost: .get) { result in
                
                DispatchQueue.main.async {
                    self.updateDataSpinner.stopAnimating()
                    
                    switch result {
                    case .success(let receivedDictionary):
                        print("Dictionary: \(receivedDictionary)")
                        self.parseNewData(receivedDictionary: receivedDictionary)
                    case .failure(let error):
                        Log.info("185 Error. \(error.localizedDescription)")
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "BuyViewController row 210", key: "context")
                        }
                    }
                }
            }
        }
    }
    
    func parseNewData(receivedDictionary:NSDictionary) {
        
        if let receivedEntity = receivedDictionary["data"] as? NSDictionary {
            // Entities received in expected format.
            var someDetailsHaveChanged = false
            var paymentModeChanged = false

            guard
                let depositCode = receivedEntity["deposit_code"] as? String,
                let partnerIban = receivedEntity["iban"] as? String,
                let partnerSwift = receivedEntity["swift"] as? String
            else {
                return
            }

            let lightningAddressUsername = receivedEntity["lightning_address_username"] as? String
            let paymentMode = receivedEntity["payment_mode"] as? String
                
            for (index, eachExistingEntity) in self.allIbanEntities.enumerated() {
                if eachExistingEntity.yourUniqueCode == depositCode {
                    if partnerIban != eachExistingEntity.ourIbanNumber || partnerSwift != eachExistingEntity.ourSwift || lightningAddressUsername != eachExistingEntity.lightningAddressUsername {
                        // Details have changed.
                        someDetailsHaveChanged = true
                        
                        // Update details in BuyVC.
                        self.allIbanEntities[index].ourIbanNumber = partnerIban
                        self.allIbanEntities[index].ourSwift = partnerSwift
                        self.allIbanEntities[index].lightningAddressUsername = lightningAddressUsername ?? self.allIbanEntities[index].lightningAddressUsername
                        
                        // Update details in CoreVC.
                        for (walletIndex, eachWalletEntity) in self.coreVC!.bittrWallet.ibanEntities.enumerated() {
                            if eachWalletEntity.yourUniqueCode == depositCode {
                                self.coreVC!.bittrWallet.ibanEntities[walletIndex].ourIbanNumber = partnerIban
                                self.coreVC!.bittrWallet.ibanEntities[walletIndex].ourSwift = partnerSwift
                                self.coreVC!.bittrWallet.ibanEntities[walletIndex].lightningAddressUsername = lightningAddressUsername ?? self.coreVC!.bittrWallet.ibanEntities[walletIndex].lightningAddressUsername
                            }
                        }
                        
                        // Update details in cache.
                        CacheManager.addBittrIban(ibanID: eachExistingEntity.id, ourIban: partnerIban, ourSwift: partnerSwift, yourCode: depositCode, lightningAddressUsername: lightningAddressUsername)
                    }

                    // Payout mode is tracked independently of the IBAN/SWIFT details above.
                    if let paymentMode = paymentMode, paymentMode != eachExistingEntity.paymentMode {
                        paymentModeChanged = true
                        self.allIbanEntities[index].paymentMode = paymentMode
                        for (walletIndex, eachWalletEntity) in self.coreVC!.bittrWallet.ibanEntities.enumerated() {
                            if eachWalletEntity.yourUniqueCode == depositCode {
                                self.coreVC!.bittrWallet.ibanEntities[walletIndex].paymentMode = paymentMode
                            }
                        }
                        CacheManager.setPaymentMode(ibanID: eachExistingEntity.id, paymentMode: paymentMode)
                    }
                }
            }

            if someDetailsHaveChanged {
                // Data has been updated.
                self.parseIbanEntities(uponPageLaunch: false)
                self.showAlert(presentingController: self, title: Language.getWord(withID: "buyvcupdatedetails"), message: Language.getWord(withID: "buyvcupdatedetails2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            } else if paymentModeChanged {
                // Only the payout mode changed (e.g. toggled on another device) — refresh
                // the toggle silently, no "details updated" alert.
                self.ibanCollectionView.reloadData()
            }
        } else {
            // Data received in wrong format.
            SentrySDK.capture(message: "Received BuyVC details in wrong format") { scope in
                scope.setExtra(value: "BuyViewController row 275", key: "context")
                scope.setExtra(value: receivedDictionary, key: "received_data")
            }
        }
    }
    
    // MARK: - Payout mode (PATCH /customer/payment-mode)

    func setPaymentMode(for entity: IbanEntity, newMode: String, isRetry: Bool = false) {

        // The lightning node must be running to sign the request.
        guard BitcoinManager.shared.ldkNode != nil, let pubkey = BitcoinManager.shared.nodeId() else {
            self.ibanCollectionView.reloadData() // revert the optimistic toggle
            // TODO: localize the title once the key is added to Language.swift.
            self.showAlert(presentingController: self, title: "Lightning not ready", message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }

        let depositCode = entity.yourUniqueCode
        let timestamp = Int(Date().timeIntervalSince1970)
        let message = "payment_mode:\(pubkey):\(depositCode):\(newMode):\(timestamp)"

        self.updateDataSpinner.startAnimating()

        Task {
            let signature: String
            do {
                signature = try await BitcoinManager.shared.signMessage(message: message)
            } catch {
                DispatchQueue.main.async {
                    self.updateDataSpinner.stopAnimating()
                    self.handlePaymentModeError(error.localizedDescription)
                }
                return
            }

            let url = "\(EnvironmentConfig.bittrAPIBaseURL)/customer/payment-mode"
            let parameters: [String: Any] = [
                "deposit_code": depositCode,
                "payment_mode": newMode,
                "pubkey": pubkey,
                "signature": signature,
                "timestamp": timestamp
            ]

            await CallsManager.makeApiCall(url: url, parameters: parameters, getOrPost: .patch) { result in
                DispatchQueue.main.async {
                    self.updateDataSpinner.stopAnimating()

                    switch result {
                    case .success(let receivedDictionary):
                        // Success shape mirrors GET /deposit_code: { data: { payment_mode: ... } }
                        if let data = receivedDictionary["data"] as? NSDictionary,
                           let confirmedMode = data["payment_mode"] as? String {
                            self.applyPaymentMode(confirmedMode, to: entity)
                        } else {
                            // Error envelope is { success: false, error: "..." }; some
                            // signed endpoints use "message" instead, so check both.
                            let serverError = (receivedDictionary["error"] as? String) ?? (receivedDictionary["message"] as? String) ?? "Unknown error"
                            if serverError.lowercased().contains("expired timestamp"), !isRetry {
                                // Stale timestamp — rebuild with a fresh one and retry once.
                                self.setPaymentMode(for: entity, newMode: newMode, isRetry: true)
                                return
                            }
                            self.handlePaymentModeError(serverError)
                        }
                    case .failure(let error):
                        self.handlePaymentModeError(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func applyPaymentMode(_ mode: String, to entity: IbanEntity) {

        entity.paymentMode = mode
        for (index, eachEntity) in self.allIbanEntities.enumerated() where eachEntity.yourUniqueCode == entity.yourUniqueCode {
            self.allIbanEntities[index].paymentMode = mode
        }
        if let coreVC = self.coreVC {
            for (index, eachEntity) in coreVC.bittrWallet.ibanEntities.enumerated() where eachEntity.yourUniqueCode == entity.yourUniqueCode {
                coreVC.bittrWallet.ibanEntities[index].paymentMode = mode
            }
        }
        CacheManager.setPaymentMode(ibanID: entity.id, paymentMode: mode)
        self.ibanCollectionView.reloadData()
    }

    private func handlePaymentModeError(_ message: String) {
        // Revert the optimistic toggle to the last server-confirmed value.
        self.ibanCollectionView.reloadData()
        // TODO: localize the title once the key is added to Language.swift.
        self.showAlert(presentingController: self, title: "Couldn't update payout mode", message: message, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }

    func changeColors() {

        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.subtitleLabel.textColor = Colors.getColor("blackorwhite")
        self.emptyLabel.textColor = Colors.getColor("blackorwhite")
        self.headerLabel.textColor = Colors.getColor("whiteoryellow")
        self.updateDataSpinner.color = Colors.getColor("whiteoryellow")
        
        if CacheManager.darkModeIsOn() {
            self.headerIcon.image = UIImage(named: "iconpiggyyellow")
            self.downIcon.image = UIImage(named: "downarrow32yellow")
        }
    }
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "buybitcoin")
        self.subtitleLabel.text = Language.getWord(withID: "buysubtitle")
        self.emptyLabel.text = Language.getWord(withID: "buyempty")
    }
}
