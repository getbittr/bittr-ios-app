//
//  MoveViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class MoveViewController: UIViewController {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    
    @IBOutlet weak var leftCard: UIView!
    @IBOutlet weak var rightCard: UIView!
    
    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var btcSlider: UISlider!
    @IBOutlet weak var btcBalance: UILabel!
    @IBOutlet weak var btcEuro: UILabel!
    @IBOutlet weak var btclnBalance: UILabel!
    @IBOutlet weak var btclnEuro: UILabel!
    @IBOutlet weak var conversionLabel: UILabel!
    
    @IBOutlet weak var receiveButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    
    var timer:Timer? = nil
    var btcStatus:Float = 7255647
    var totalStatus:Float = 9521948
    var presetAmount:Double?
    
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
    
    var homeVC:HomeViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        receiveButton.setTitle("", for: .normal)
        sendButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        leftCard.layer.cornerRadius = 13
        rightCard.layer.cornerRadius = 13
        
        totalStatus = Float(fetchedBtcBalance + fetchedBtclnBalance)
        btcSlider.maximumValue = totalStatus
        btcSlider.minimumValue = 0
        btcSlider.value = Float(fetchedBtcBalance)
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        
        
        var fetchedBtcString = "\(fetchedBtcBalance.rounded() * 0.00000001)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)
        var fetchedBtclnString = "\(fetchedBtclnBalance.rounded() * 0.00000001)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)
        var fetchedTotalString = "\((fetchedBtcBalance.rounded()+fetchedBtclnBalance.rounded()) * 0.00000001)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)
        
        
        
        btcBalance.text = "\(numberFormatter.number(from: fetchedBtcString)!.decimalValue as NSNumber)"
        btcBalance.text = "\(CGFloat(Int(fetchedBtcBalance)) * 0.00000001)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "")
        //btclnBalance.text = "\(numberFormatter.number(from: fetchedBtclnString)!.decimalValue as NSNumber)"
        btclnBalance.text = "\(CGFloat(Int(fetchedBtclnBalance)) * 0.00000001)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "")
        balanceLabel.text = "\(numberFormatter.number(from: fetchedTotalString)!.decimalValue as NSNumber) btc"
        
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
        conversionLabel.text = currencySymbol + " " + balanceValue
        btcEuro.text = currencySymbol + " " + btcBalanceValue
        btclnEuro.text = currencySymbol + " " + btclnBalanceValue
        
        viewTotal.layer.cornerRadius = 13
        viewRegular.layer.cornerRadius = 13
        viewInstant.layer.cornerRadius = 13
        yellowCard.layer.cornerRadius = 20
        
        yellowCard.layer.shadowColor = UIColor.black.cgColor
        yellowCard.layer.shadowOffset = CGSize(width: 0, height: 7)
        yellowCard.layer.shadowRadius = 10.0
        yellowCard.layer.shadowOpacity = 0.1
        
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
    
    @IBAction func sliderValueHasChanged(_ sender: UISlider) {
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        btcBalance.text = "\(numberFormatter.number(from: "\(sender.value.rounded() * 0.00000001)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "")
        btclnBalance.text = "\(numberFormatter.number(from: "\((btcSlider.maximumValue - sender.value.rounded()) * 0.00000001)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "")
        
        var correctValue:CGFloat = self.eurValue
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctValue = self.chfValue
            currencySymbol = "CHF"
        }
        var eurBalanceValue = String(Int(((CGFloat(sender.value.rounded()/btcSlider.maximumValue.rounded()))*(fetchedBtcBalance+fetchedBtclnBalance)*0.00000001*correctValue).rounded()))
        var eurLnBalanceValue = String(Int(((1-(CGFloat(sender.value.rounded()/btcSlider.maximumValue.rounded())))*(fetchedBtcBalance+fetchedBtclnBalance)*0.00000001*correctValue).rounded()))
        
        btcEuro.text = currencySymbol + " " + eurBalanceValue
        btclnEuro.text = currencySymbol + " " + eurLnBalanceValue
        
        self.presetAmount = (Double(totalStatus - Float(fetchedBtcBalance)) - Double(totalStatus - sender.value.rounded())) * 0.00000001
        if self.presetAmount ?? 0 < 0 {
            self.presetAmount = 0
        }
        
        /*debounce(seconds: 1) {
            self.sendButtonTapped(self)
        }*/
    }
    
    @IBAction func sliderTouchUpInside(_ sender: UISlider) {
        //self.sendButtonTapped(self)
    }
    
    @IBAction func receiveButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "MoveToReceive", sender: self)
    }
    
    @IBAction func sendButtonTapped(_ sender: Any) {
        performSegue(withIdentifier: "MoveToSend", sender: self)
    }
    
    /*func debounce(seconds: TimeInterval, function: @escaping () -> Swift.Void ) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false, block: { _ in
            function()
        })
    }*/
    
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
    
}
