//
//  MoveViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class MoveViewController: UIViewController {

    // Elements
    @IBOutlet weak var channelButton: UIButton!
    @IBOutlet weak var subtitleLabel: UILabel!
    
    // Send and Receive buttons
    @IBOutlet weak var leftCard: UIView! // Send Button View
    @IBOutlet weak var rightCard: UIView! // Receive Button View
    @IBOutlet weak var receiveButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var sendLabel: UILabel!
    @IBOutlet weak var receiveLabel: UILabel!
    
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
    var swapVC:SwapViewController?
    
    // Values
    var maximumReceivableLNSats:Int?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.subtitleLabel.accessibilityIdentifier = TestID.Move.subtitleLabel
        self.satsTotal.accessibilityIdentifier = TestID.Move.satsTotal
        self.swapButton.accessibilityIdentifier = TestID.Move.swapButton
        self.swapButton.accessibilityLabel = "Swap"

        // Set language and colors.
        self.setBasicStyling()
        self.updateLabels()
        self.changeColors()
        self.setWords()
        self.addHeader(iconLight: "iconpiggywhite", iconDark: "iconpiggyyellow", title: Language.getWord(withID: "balance"))
    }
    
    func updateLabels() {
        
        // Calculate balance values.
        let correctBtcBalance:CGFloat = self.coreVC!.bittrWallet.satoshisOnchain.inBTC()
        let correctBtclnBalance:CGFloat = self.coreVC!.bittrWallet.satoshisLightning.inBTC()
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
            }
        } else if segue.identifier == "MoveToReceive" {
            if let receiveVC = segue.destination as? ReceiveViewController {
                receiveVC.maximumReceivableLNSats = self.maximumReceivableLNSats
                receiveVC.homeVC = self.homeVC
                receiveVC.coreVC = self.coreVC
                self.coreVC?.receiveVC = receiveVC
            }
        } else if segue.identifier == "MoveToSwap" {
            if let swapVC = segue.destination as? SwapViewController {
                swapVC.homeVC = self.homeVC
                swapVC.coreVC = self.coreVC
                self.swapVC = swapVC
                self.coreVC?.swapVC = swapVC
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
