//
//  MoveViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class MoveViewController: UIViewController {

    // Elements
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var channelButton: UIButton!
    @IBOutlet weak var subtitleLabel: UILabel!
    
    // Send and Receive buttons
    @IBOutlet weak var leftCard: UIView! // Send Button View
    @IBOutlet weak var rightCard: UIView! // Receive Button View
    @IBOutlet weak var receiveButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var sendLabel: UILabel!
    @IBOutlet weak var receiveLabel: UILabel!
    
    // Values
    var maximumSendableLNSats:Int?
    var maximumReceivableLNSats:Int?
    
    // Views
    @IBOutlet weak var yellowCard: UIView!
    @IBOutlet weak var viewTotal: UIView!
    @IBOutlet weak var viewRegular: UIView!
    @IBOutlet weak var viewInstant: UIView!
    @IBOutlet weak var satsTotal: UILabel!
    @IBOutlet weak var satsRegular: UILabel!
    @IBOutlet weak var satsInstant: UILabel!
    @IBOutlet weak var conversionTotal: UILabel!
    @IBOutlet weak var conversionRegular: UILabel!
    @IBOutlet weak var conversionInstant: UILabel!
    @IBOutlet weak var questionMark: UIImageView!
    
    // Swap view
    @IBOutlet weak var swapView: UIView!
    @IBOutlet weak var swapButton: UIButton!
    @IBOutlet weak var swapIcon: UIImageView!
    
    // Labels
    @IBOutlet weak var labelRegular: UILabel!
    @IBOutlet weak var labelInstant: UILabel!
    
    // Home View Controller
    var coreVC:CoreViewController?
    var homeVC:HomeViewController?
    var isFromBackgroundNotification = false
    var isFromLightningPayment = false
    var pendingLightningInvoice = ""
    var isFromOnchainPayment = false
    var pendingOnchainAddress = ""
    var pendingOnchainAmount = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Button titles.
        self.downButton.setTitle("", for: .normal)
        self.receiveButton.setTitle("", for: .normal)
        self.sendButton.setTitle("", for: .normal)
        self.channelButton.setTitle("", for: .normal)
        self.swapButton.setTitle("", for: .normal)
        
        // Corner radii
        self.leftCard.layer.cornerRadius = 8
        self.rightCard.layer.cornerRadius = 8
        self.viewTotal.layer.cornerRadius = 13
        self.viewRegular.layer.cornerRadius = 13
        self.viewInstant.layer.cornerRadius = 13
        self.yellowCard.layer.cornerRadius = 20
        self.swapView.layer.cornerRadius = self.swapView.bounds.height/2
        
        // Yellow card shadow.
        self.yellowCard.layer.shadowColor = UIColor.black.cgColor
        self.yellowCard.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.yellowCard.layer.shadowRadius = 10.0
        self.yellowCard.layer.shadowOpacity = 0.1
        
        // Swap view shadow
        self.swapView.layer.shadowColor = UIColor.black.cgColor
        self.swapView.layer.shadowOffset = CGSize(width: 0, height: 5)
        self.swapView.layer.shadowRadius = 8
        self.swapView.layer.shadowOpacity = 0.1
        
        self.updateLabels()
        self.changeColors()
        
        // If we're coming from a Lightning payment, automatically trigger the swap segue
        if self.isFromLightningPayment && !self.pendingLightningInvoice.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.performSegue(withIdentifier: "MoveToSwap", sender: self)
            }
        }
        
        // If we're coming from an onchain payment, automatically trigger the swap segue
        if self.isFromOnchainPayment && !self.pendingOnchainAddress.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.performSegue(withIdentifier: "MoveToSwap", sender: self)
            }
        }
    }
    
    func updateLabels() {
        
        // Calculate balance values.
        let correctBtcBalance:CGFloat = CGFloat(self.coreVC!.bittrWallet.satoshisOnchain) * 0.00000001
        let correctBtclnBalance:CGFloat = CGFloat(self.coreVC!.bittrWallet.satoshisLightning) * 0.00000001
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        let balanceValue = String(Int(((correctBtcBalance+correctBtclnBalance)*bitcoinValue.currentValue).rounded())).addSpaces()
        let btcBalanceValue = String(Int(((correctBtcBalance)*bitcoinValue.currentValue).rounded())).addSpaces()
        let btclnBalanceValue = String(Int(((correctBtclnBalance)*bitcoinValue.currentValue).rounded())).addSpaces()
        
        // Show balance values.
        self.satsTotal.text = "\(self.coreVC!.bittrWallet.satoshisOnchain + self.coreVC!.bittrWallet.satoshisLightning)".addSpaces() + " sats"
        self.satsRegular.text = "\(self.coreVC!.bittrWallet.satoshisOnchain)".addSpaces() + " sats"
        self.satsInstant.text = "\(self.coreVC!.bittrWallet.satoshisLightning)".addSpaces() + " sats"
        self.conversionTotal.text = bitcoinValue.chosenCurrency + " " + balanceValue
        self.conversionRegular.text = bitcoinValue.chosenCurrency + " " + btcBalanceValue
        self.conversionInstant.text = bitcoinValue.chosenCurrency + " " + btclnBalanceValue
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func receiveButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "MoveToReceive", sender: self)
    }
    
    @IBAction func sendButtonTapped(_ sender: Any) {
        performSegue(withIdentifier: "MoveToSend", sender: self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "MoveToSend" {
            if let sendVC = segue.destination as? SendViewController {
                sendVC.coreVC = self.coreVC
                sendVC.maximumSendableLNSats = self.maximumSendableLNSats
                sendVC.homeVC = self.homeVC
            }
        } else if segue.identifier == "MoveToReceive" {
            if let receiveVC = segue.destination as? ReceiveViewController {
                receiveVC.maximumReceivableLNSats = self.maximumReceivableLNSats
                receiveVC.homeVC = self.homeVC
                receiveVC.coreVC = self.coreVC
            }
        } else if segue.identifier == "MoveToSwap" {
            if let swapVC = segue.destination as? SwapViewController {
                swapVC.homeVC = self.homeVC
                swapVC.coreVC = self.coreVC
                swapVC.isFromBackgroundNotification = self.isFromBackgroundNotification
                swapVC.isFromLightningPayment = self.isFromLightningPayment
                swapVC.pendingLightningInvoice = self.pendingLightningInvoice
                swapVC.isFromOnchainPayment = self.isFromOnchainPayment
                swapVC.pendingOnchainAddress = self.pendingOnchainAddress
                swapVC.pendingOnchainAmount = self.pendingOnchainAmount
                print("DEBUG - MoveViewController: Performing segue to SwapViewController with address: \(self.pendingOnchainAddress), amount: \(self.pendingOnchainAmount)")
                
                // Clear the pending data after passing it to prevent it from being reused
                if self.isFromLightningPayment || self.isFromOnchainPayment {
                    print("DEBUG - Clearing pending data in MoveViewController after passing to SwapViewController")
                    self.pendingLightningInvoice = ""
                    self.pendingOnchainAddress = ""
                    self.pendingOnchainAmount = 0
                    self.isFromLightningPayment = false
                    self.isFromOnchainPayment = false
                }
            }
        }
    }
    
    @IBAction func channelButtonTapped(_ sender: UIButton) {
        
        if self.coreVC!.bittrWallet.lightningChannels.count == 0 {
            // There is no Lightning channel.
            self.coreVC!.launchQuestion(question: Language.getWord(withID: "lightningchannels"), answer: Language.getWord(withID: "lightningexplanation1"), type: nil)
        } else {
            // There's a Lightning channel.
            self.coreVC!.launchQuestion(question: Language.getWord(withID: "lightningchannel"), answer: Language.getWord(withID: "lightningexplanation1"), type: "lightningexplanation")
        }
    }
    
    @IBAction func swapButtonTapped(_ sender: UIButton) {
        
        if self.coreVC!.bittrWallet.lightningChannels.count == 0 {
            // There is no Lightning channel.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "instantpayments"), message: Language.getWord(withID: "questionvc13"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        } else {
            self.performSegue(withIdentifier: "MoveToSwap", sender: self)
        }
    }
    
}
