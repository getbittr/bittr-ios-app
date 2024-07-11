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
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var channelButton: UIButton!
    
    // Send and Receive buttons
    @IBOutlet weak var leftCard: UIView! // Send Button View
    @IBOutlet weak var rightCard: UIView! // Receive Button View
    @IBOutlet weak var receiveButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    
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
    
    // Home View Controller
    var homeVC:HomeViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii and button titles.
        downButton.setTitle("", for: .normal)
        receiveButton.setTitle("", for: .normal)
        sendButton.setTitle("", for: .normal)
        channelButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        leftCard.layer.cornerRadius = 13
        rightCard.layer.cornerRadius = 13
        viewTotal.layer.cornerRadius = 13
        viewRegular.layer.cornerRadius = 13
        viewInstant.layer.cornerRadius = 13
        yellowCard.layer.cornerRadius = 20
        
        // Yellow card shadow.
        yellowCard.layer.shadowColor = UIColor.black.cgColor
        yellowCard.layer.shadowOffset = CGSize(width: 0, height: 7)
        yellowCard.layer.shadowRadius = 10.0
        yellowCard.layer.shadowOpacity = 0.1
        
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
            let notificationDict:[String: Any] = ["question":"lightning channels","answer":"To send and receive Bitcoin Lightning payments, you need to have at least one Lightning channel with anyone.\n\nTo open a channel with Bittr, buy bitcoin worth up to 100 Swiss Francs or Euros. Check your wallet's Buy section or getbittr.com for all information."]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
        } else {
            // There's a Lightning channel.
            let notificationDict:[String: Any] = ["question":"lightning channel","answer":"To send and receive Bitcoin Lightning payments, you need to have at least one Lightning channel with anyone.\n\nTo open a channel with Bittr, buy bitcoin worth up to 100 Swiss Francs or Euros. Check your wallet's Buy section or getbittr.com for all information.","type":"lightningexplanation"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
        }
    }
    
}
