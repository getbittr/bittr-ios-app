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
    
    @IBOutlet weak var receiveButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    
    var timer:Timer? = nil
    var btcStatus:Float = 7255647
    var totalStatus:Float = 9521948
    var presetAmount:Double?
    
    var fetchedBtcBalance:CGFloat = 0.0
    var fetchedBtclnBalance:CGFloat = 0.0
    
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
        
        btcBalance.text = String(fetchedBtcBalance.rounded() * 0.00000001)
        btclnBalance.text = String(fetchedBtclnBalance.rounded() * 0.00000001)
        balanceLabel.text = String((fetchedBtcBalance.rounded()+fetchedBtclnBalance.rounded()) * 0.00000001) + " btc"
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func sliderValueHasChanged(_ sender: UISlider) {
        
        btcBalance.text = String("\(sender.value.rounded() * 0.00000001)")
        btclnBalance.text = String("\((btcSlider.maximumValue - sender.value.rounded()) * 0.00000001)")
        //btcEuro.text = String("€ \(Int(((sender.value/btcSlider.maximumValue) * 2625).rounded()))")
        //btclnEuro.text = String("€ \(Int(((1-(sender.value/btcSlider.maximumValue)) * 2625).rounded()))")
        
        self.presetAmount = (Double(totalStatus - Float(fetchedBtcBalance)) - Double(totalStatus - sender.value.rounded())) * 0.00000001
        if self.presetAmount ?? 0 < 0 {
            self.presetAmount = 0
        }
        
        debounce(seconds: 1) {
            self.sendButtonTapped(self)
        }
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
    
    func debounce(seconds: TimeInterval, function: @escaping () -> Swift.Void ) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false, block: { _ in
            function()
        })
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "MoveToSend" {
            
            let sendVC = segue.destination as? SendViewController
            if let actualSendVC = sendVC {
                if let actualPresetAmount = self.presetAmount {
                    actualSendVC.presetAmount = actualPresetAmount
                }
            }
        }
    }
    
}
