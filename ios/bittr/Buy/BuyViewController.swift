//
//  BuyViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit
import UserNotifications

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
        self.allIbanEntities = []
        for eachIbanEntity in BitcoinManager.shared.bittrWallet.ibanEntities where eachIbanEntity.yourUniqueCode != "" {
            self.allIbanEntities += [eachIbanEntity]
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
            
            let thisIbanEntity = self.allIbanEntities[indexPath.row]
            cell.ibanEntity = thisIbanEntity
            cell.buyVC = self
            
            cell.labelYourEmail.text = thisIbanEntity.yourEmail
            cell.labelYourIban.text = thisIbanEntity.yourIbanNumber
            cell.labelOurIban.text = thisIbanEntity.ourIbanNumber
            cell.labelOurName.text = thisIbanEntity.ourName
            cell.labelYourCode.text = thisIbanEntity.yourUniqueCode
            
            cell.ibanButton.boundString = thisIbanEntity.ourIbanNumber
            cell.nameButton.boundString = thisIbanEntity.ourName
            cell.codeButton.boundString = thisIbanEntity.yourUniqueCode
            
            // Reset the toggle to a settled, server-confirmed state. Re-enabling
            // here is what clears the in-flight lock set in didChangePaymentModeSwitch
            // (so a reload after success/failure makes the switch interactive again).
            cell.paymentModeSpinner.stopAnimating()
            cell.paymentModeSwitch.isEnabled = true
            if thisIbanEntity.paymentMode != "onchain" {
                cell.paymentModeSwitch.isOn = true
            } else {
                cell.paymentModeSwitch.isOn = false
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
        return CGSize(width: cellWidth, height: 340)
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
                    SentryManager.capture(error, context: "BuyViewController row 203")
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
                        Log.debug("Dictionary: \(receivedDictionary)")
                        self.parseNewData(receivedDictionary: receivedDictionary)
                    case .failure(let error):
                        Log.info("185 Error. \(error.localizedDescription)")
                        SentryManager.capture(error, context: "BuyViewController row 210")
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
            var changedPaymentModeIndexPaths = [IndexPath]()

            guard
                let depositCode = receivedEntity["deposit_code"] as? String,
                let partnerIban = receivedEntity["iban"] as? String,
                let partnerSwift = receivedEntity["swift"] as? String
            else {
                return
            }

            let lightningAddressUsername = receivedEntity["lightning_address_username"] as? String
            let paymentMode = receivedEntity["payment_mode"] as? String
                
            for (index, eachExistingEntity) in self.allIbanEntities.enumerated() where eachExistingEntity.yourUniqueCode == depositCode {
                
                if partnerIban != eachExistingEntity.ourIbanNumber || partnerSwift != eachExistingEntity.ourSwift || lightningAddressUsername != eachExistingEntity.lightningAddressUsername {
                    // Details have changed.
                    someDetailsHaveChanged = true
                    
                    // Update details in BuyVC.
                    self.allIbanEntities[index].ourIbanNumber = partnerIban
                    self.allIbanEntities[index].ourSwift = partnerSwift
                    self.allIbanEntities[index].lightningAddressUsername = lightningAddressUsername ?? self.allIbanEntities[index].lightningAddressUsername
                    
                    // Update details in CoreVC.
                    for (walletIndex, eachWalletEntity) in BitcoinManager.shared.bittrWallet.ibanEntities.enumerated() where eachWalletEntity.yourUniqueCode == depositCode {
                        BitcoinManager.shared.bittrWallet.ibanEntities[walletIndex].ourIbanNumber = partnerIban
                        BitcoinManager.shared.bittrWallet.ibanEntities[walletIndex].ourSwift = partnerSwift
                        BitcoinManager.shared.bittrWallet.ibanEntities[walletIndex].lightningAddressUsername = lightningAddressUsername ?? BitcoinManager.shared.bittrWallet.ibanEntities[walletIndex].lightningAddressUsername
                    }
                    
                    // Update details in cache.
                    CacheManager.addBittrIban(ibanID: eachExistingEntity.id, ourIban: partnerIban, ourSwift: partnerSwift, yourCode: depositCode, lightningAddressUsername: lightningAddressUsername)

                    // Payout mode is tracked independently of the IBAN/SWIFT details above.
                    if let paymentMode = paymentMode, paymentMode != eachExistingEntity.paymentMode {
                        paymentModeChanged = true
                        changedPaymentModeIndexPaths.append(IndexPath(item: index, section: 0))
                        self.allIbanEntities[index].paymentMode = paymentMode
                        for (walletIndex, eachWalletEntity) in BitcoinManager.shared.bittrWallet.ibanEntities.enumerated() where eachWalletEntity.yourUniqueCode == depositCode {
                            BitcoinManager.shared.bittrWallet.ibanEntities[walletIndex].paymentMode = paymentMode
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
                // just the affected card(s) silently, no "details updated" alert.
                self.ibanCollectionView.reloadItems(at: changedPaymentModeIndexPaths)
            }
        } else {
            // Data received in wrong format.
            SentryManager.capture("Received BuyVC details in wrong format", context: "BuyViewController row 275")
        }
    }
    
    // MARK: - Payout mode (PATCH /customer/payment-mode)

    func setPaymentMode(for entity: IbanEntity, newMode: String) {
        if newMode == "lightning" {
            self.hasAcceptedPushNotifications { hasAccepted in
                if hasAccepted {
                    self.proceedWithApiCall(for: entity, newMode: newMode)
                } else {
                    Log.info("Notifications not authorized; blocking switch to lightning.")
                    self.reloadCard(for: entity)
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "receivenotifications"), message: Language.getWord(withID: "lightningneedsnotifications"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            }
        } else {
            self.proceedWithApiCall(for: entity, newMode: newMode)
        }
    }
    
    func hasAcceptedPushNotifications(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }
    
    func proceedWithApiCall(for entity: IbanEntity, newMode: String, isRetry: Bool = false) {
        // The lightning node must be running to sign the request.
        guard BitcoinManager.shared.ldkNode != nil, let pubkey = BitcoinManager.shared.nodeId() else {
            Log.info("Lightning not ready for payment mode update.")
            self.reloadCard(for: entity) // revert the optimistic toggle
            self.showAlert(presentingController: self, title: Language.getWord(withID: "lightningnotready"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        let depositCode = entity.yourUniqueCode
        let timestamp = Int(Date().timeIntervalSince1970)
        let message = "payment_mode:\(pubkey):\(depositCode):\(newMode):\(timestamp)"

        // The per-card spinner next to the switch (started in the cell's
        // didChangePaymentModeSwitch) is the only progress indicator; it's
        // cleared when the card reloads with the server-confirmed value.
        Task {
            let signature: String
            do {
                signature = try await BitcoinManager.shared.signMessage(message: message)
            } catch {
                DispatchQueue.main.async {
                    self.handlePaymentModeError(error.localizedDescription, for: entity)
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

            Log.info("Will make payment mode update API call.")
            await CallsManager.makeApiCall(url: url, parameters: parameters, getOrPost: .patch) { result in
                DispatchQueue.main.async {

                    switch result {
                    case .success(let receivedDictionary):
                        // Success shape mirrors GET /deposit_code: { data: { payment_mode: ... } }
                        if let data = receivedDictionary["data"] as? NSDictionary,
                           let confirmedMode = data["payment_mode"] as? String {
                            Log.info("Payment mode successfully updated.")
                            self.applyPaymentMode(confirmedMode, to: entity)
                        } else {
                            Log.info("Did receive payment mode API server error.")
                            
                            // Error envelope is { success: false, error: "..." }; some
                            // signed endpoints use "message" instead, so check both.
                            let serverError = (receivedDictionary["error"] as? String) ?? (receivedDictionary["message"] as? String) ?? "Unknown error"
                            
                            // Send to Sentry.
                            SentryManager.capture("Error updating payment mode: \(serverError)", context: "BuyViewController row 367")
                            
                            // Retry.
                            if serverError.lowercased().contains("expired timestamp"), !isRetry {
                                // Stale timestamp — rebuild with a fresh one and retry once.
                                self.proceedWithApiCall(for: entity, newMode: newMode, isRetry: true)
                                return
                            }
                            self.handlePaymentModeError(serverError, for: entity)
                        }
                    case .failure(let error):
                        self.handlePaymentModeError(error.localizedDescription, for: entity)
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
        for (index, eachEntity) in BitcoinManager.shared.bittrWallet.ibanEntities.enumerated() where eachEntity.yourUniqueCode == entity.yourUniqueCode {
            BitcoinManager.shared.bittrWallet.ibanEntities[index].paymentMode = mode
        }
        CacheManager.setPaymentMode(ibanID: entity.id, paymentMode: mode)
        self.reloadCard(for: entity)
    }

    private func handlePaymentModeError(_ message: String, for entity: IbanEntity) {
        Log.info("Will handle payment mode error.")
        // Revert the optimistic toggle to the last server-confirmed value.
        self.reloadCard(for: entity)
        self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentmodeupdateerror"), message: message, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }

    /// Reload just the card for this deposit code (keeps the other cards + the
    /// horizontal scroll position; falls back to a full reload if not found).
    private func reloadCard(for entity: IbanEntity) {
        if let index = self.allIbanEntities.firstIndex(where: { $0.yourUniqueCode == entity.yourUniqueCode }) {
            self.ibanCollectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        } else {
            self.ibanCollectionView.reloadData()
        }
    }
    
    @IBAction func paymentModeQuestionTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        self.showAlert(presentingController: self, title: Language.getWord(withID: "buyvclightning"), message: Language.getWord(withID: "buyvclightningexplanation"), buttons: [Language.getWord(withID: "okay")], actions: nil)
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
