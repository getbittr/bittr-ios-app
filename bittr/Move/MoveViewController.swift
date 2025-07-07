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
    var fetchedBtcBalance:CGFloat = 0.0
    var fetchedBtclnBalance:CGFloat = 0.0
    var eurValue:CGFloat = 0.0
    var chfValue:CGFloat = 0.0
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
        
        // Calculate balance values.
        let correctBtcBalance:CGFloat = fetchedBtcBalance * 0.00000001
        let correctBtclnBalance:CGFloat = fetchedBtclnBalance * 0.00000001
        var correctValue:CGFloat = self.eurValue
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctValue = self.chfValue
            currencySymbol = "CHF"
        }
        var balanceValue = String(Int(((correctBtcBalance+correctBtclnBalance)*correctValue).rounded()))
        var btcBalanceValue = String(Int(((correctBtcBalance)*correctValue).rounded()))
        var btclnBalanceValue = String(Int(((correctBtclnBalance)*correctValue).rounded()))
        
        // Show balance values.
        satsTotal.text = addSpacesToString(balanceValue: "\(Int(fetchedBtcBalance + fetchedBtclnBalance))") + " sats"
        satsRegular.text = addSpacesToString(balanceValue: "\(Int(fetchedBtcBalance))") + " sats"
        satsInstant.text = addSpacesToString(balanceValue: "\(Int(fetchedBtclnBalance))") + " sats"
        conversionTotal.text = currencySymbol + " " + balanceValue
        conversionRegular.text = currencySymbol + " " + btcBalanceValue
        conversionInstant.text = currencySymbol + " " + btclnBalanceValue
        
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
            
            let sendVC = segue.destination as? SendViewController
            if let actualSendVC = sendVC {
                actualSendVC.btcAmount = fetchedBtcBalance.rounded() * 0.00000001
                actualSendVC.btclnAmount = fetchedBtclnBalance.rounded() * 0.00000001
                
                actualSendVC.eurValue = self.eurValue
                actualSendVC.chfValue = self.chfValue
                
                actualSendVC.maximumSendableLNSats = self.maximumSendableLNSats
                if actualSendVC.maximumSendableLNSats! < 0 {
                    actualSendVC.maximumSendableLNSats = 0
                }
                
                if let actualHomeVC = self.homeVC {
                    actualSendVC.homeVC = actualHomeVC
                }
            }
        } else if segue.identifier == "MoveToReceive" {
            
            let receiveVC = segue.destination as? ReceiveViewController
            if let actualReceiveVC = receiveVC {
                actualReceiveVC.maximumReceivableLNSats = self.maximumReceivableLNSats
                actualReceiveVC.homeVC = self.homeVC
            }
        } else if segue.identifier == "MoveToSwap" {
            if let swapVC = segue.destination as? SwapViewController {
                swapVC.homeVC = self.homeVC
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
    
    func addSpacesToString(balanceValue:String) -> String {
        
        var balanceValue = balanceValue
        
        switch balanceValue.count {
        case 4:
            balanceValue = balanceValue[0] + " " + balanceValue[1..<4]
        case 5:
            balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5]
        case 6:
            balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6]
        case 7:
            balanceValue = balanceValue[0] + " " + balanceValue[1..<4] + " " + balanceValue[4..<7]
        case 8:
            balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5] + " " + balanceValue[5..<8]
        case 9:
            balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6] + " " + balanceValue[6..<9]
        default:
            balanceValue = balanceValue[0..<balanceValue.count]
        }
        
        return balanceValue
    }
    
    @IBAction func channelButtonTapped(_ sender: UIButton) {
        
        if self.satsInstant.text?.replacingOccurrences(of: "sats", with: "").replacingOccurrences(of: " ", with: "") == "0" {
            // There is no Lightning channel.
            let notificationDict:[String: Any] = ["question":Language.getWord(withID: "lightningchannels"),"answer":Language.getWord(withID: "lightningexplanation1")]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
        } else {
            // There's a Lightning channel.
            let notificationDict:[String: Any] = ["question":Language.getWord(withID: "lightningchannel"),"answer":Language.getWord(withID: "lightningexplanation1"),"type":"lightningexplanation"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
        }
    }
    
    @IBAction func swapButtonTapped(_ sender: UIButton) {
        self.performSegue(withIdentifier: "MoveToSwap", sender: self)
    }
    
}
