//
//  QuestionViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/02/2024.
//

import UIKit

class QuestionViewController: UIViewController {

    @IBOutlet weak var finalLogo: UIImageView!
    @IBOutlet weak var bittrText: UIImageView!
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var answerLabel: UILabel!
    @IBOutlet weak var answerLabelBottom: NSLayoutConstraint!
    
    // Channel chart
    @IBOutlet weak var channelView: UIView!
    @IBOutlet weak var yourBalanceLabel: UILabel!
    @IBOutlet weak var receiveLimitLabel: UILabel!
    @IBOutlet weak var totalLabel: UILabel!
    @IBOutlet weak var barView: UIView!
    @IBOutlet weak var balanceBar: UIView!
    @IBOutlet weak var balanceBarWidth: NSLayoutConstraint!
    
    var headerText:String?
    var answerText:String?
    var questionType:String?
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii and button titles
        downButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        channelView.layer.cornerRadius = 13
        barView.layer.cornerRadius = 2
        
        // Channel view shadow
        channelView.layer.shadowColor = UIColor.black.cgColor
        channelView.layer.shadowOffset = CGSize(width: 0, height: 7)
        channelView.layer.shadowRadius = 10.0
        channelView.layer.shadowOpacity = 0.1
        
        if let actualHeader = headerText, let actualAnswer = answerText {
            self.headerLabel.text = actualHeader
            self.answerLabel.text = actualAnswer
        }
        
        self.changeColors()
        
        if let actualType = questionType {
            if actualType == "lightningreceivable" {
                if let actualChannel = self.coreVC?.bittrWallet.bittrChannel {
                    
                    self.setChannelChart()
                    
                    self.answerLabel.text = "\(Language.getWord(withID: "questionvc1")) \(addSpacesToString(balanceValue:"\(actualChannel.size)")) \(Language.getWord(withID: "questionvc2")) \(addSpacesToString(balanceValue:"\(actualChannel.received+actualChannel.punishmentReserve)")) \(Language.getWord(withID: "questionvc3")) \(addSpacesToString(balanceValue:"\(actualChannel.size - actualChannel.received - actualChannel.punishmentReserve)")) \(Language.getWord(withID: "questionvc4")) \(addSpacesToString(balanceValue:"\(actualChannel.receivableMaximum)")) \(Language.getWord(withID: "questionvc5"))."
                } else {
                    self.headerLabel.text = Language.getWord(withID: "questionvc6")
                    self.answerLabel.text = Language.getWord(withID: "lightningexplanation1")
                }
            } else if actualType == "lightningsendable" {
                if let actualChannel = self.coreVC?.bittrWallet.bittrChannel {
                    
                    self.setChannelChart()
                    
                    self.answerLabel.text = "\(Language.getWord(withID: "questionvc7")) \(addSpacesToString(balanceValue:"\(actualChannel.received+actualChannel.punishmentReserve)")) \(Language.getWord(withID: "questionvc8")) \(addSpacesToString(balanceValue:"\(actualChannel.punishmentReserve)")) \(Language.getWord(withID: "questionvc9")) \(addSpacesToString(balanceValue:"\(actualChannel.received)")) \(Language.getWord(withID: "questionvc10")) \(addSpacesToString(balanceValue:"\(actualChannel.size)")) \(Language.getWord(withID: "questionvc11")) \(addSpacesToString(balanceValue:"\(actualChannel.receivableMaximum)")) sats."
                } else {
                    self.headerLabel.text = Language.getWord(withID: "questionvc12")
                    self.answerLabel.text = Language.getWord(withID: "questionvc13")
                }
            } else if actualType == "lightningexplanation" {
                if let actualChannel = self.coreVC?.bittrWallet.bittrChannel {
                    
                    self.setChannelChart()
                    
                    self.answerLabel.text = "\(Language.getWord(withID: "questionvc7")) \(addSpacesToString(balanceValue:"\(actualChannel.received+actualChannel.punishmentReserve)")) \(Language.getWord(withID: "questionvc14")) \(addSpacesToString(balanceValue:"\(actualChannel.size)")) \(Language.getWord(withID: "questionvc15")) \(addSpacesToString(balanceValue:"\(actualChannel.size - actualChannel.received - actualChannel.punishmentReserve)")) \(Language.getWord(withID: "questionvc16"))"
                }
            }
        }
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func addSpacesToString(balanceValue:String) -> String {
        
        var balanceValue = balanceValue
        
        switch balanceValue.count {
        case 4:
            balanceValue = balanceValue[0] + "." + balanceValue[1..<4]
        case 5:
            balanceValue = balanceValue[0..<2] + "." + balanceValue[2..<5]
        case 6:
            balanceValue = balanceValue[0..<3] + "." + balanceValue[3..<6]
        case 7:
            balanceValue = balanceValue[0] + "." + balanceValue[1..<4] + "." + balanceValue[4..<7]
        case 8:
            balanceValue = balanceValue[0..<2] + "." + balanceValue[2..<5] + "." + balanceValue[5..<8]
        case 9:
            balanceValue = balanceValue[0..<3] + "." + balanceValue[3..<6] + "." + balanceValue[6..<9]
        default:
            balanceValue = balanceValue[0..<balanceValue.count]
        }
        
        return balanceValue
    }
    
    func setChannelChart() {
        
        let bittrChannel = self.coreVC?.bittrWallet.bittrChannel
        self.yourBalanceLabel.text = "\(addSpacesToString(balanceValue: "\(bittrChannel!.received+bittrChannel!.punishmentReserve)"))"
        self.receiveLimitLabel.text = "\(addSpacesToString(balanceValue: "\(bittrChannel!.size - bittrChannel!.received - bittrChannel!.punishmentReserve)"))"
        self.totalLabel.text = "\(addSpacesToString(balanceValue: "\(bittrChannel!.size)")) \(Language.getWord(withID: "total")), \(addSpacesToString(balanceValue: "\(bittrChannel!.punishmentReserve)")) \(Language.getWord(withID: "reserve"))"
        
        NSLayoutConstraint.deactivate([self.balanceBarWidth])
        self.balanceBarWidth = NSLayoutConstraint(item: self.balanceBar, attribute: .width, relatedBy: .equal, toItem: self.barView, attribute: .width, multiplier: CGFloat(bittrChannel!.received+bittrChannel!.punishmentReserve)/CGFloat(bittrChannel!.size), constant: 0)
        NSLayoutConstraint.activate([self.balanceBarWidth])
        self.answerLabelBottom.constant = 140
        self.view.layoutIfNeeded()
        
        self.channelView.alpha = 1
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.answerLabel.textColor = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            // Dark mode is on.
            self.bittrText.image = UIImage(named: "bittrtextwhite")
            self.finalLogo.image = UIImage(named: "logodarkmode80")
        } else {
            // Dark mode is off.
            self.bittrText.image = UIImage(named: "bittrtext")
            self.finalLogo.image = UIImage(named: "logo80")
        }
    }
    
}
