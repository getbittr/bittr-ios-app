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
    
    var bittrChannel:Channel?
    
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
                if let actualChannel = bittrChannel {
                    
                    self.setChannelChart()
                    
                    self.answerLabel.text = "There's a limit to the amount of satoshis you can receive per invoice.\n\nThe size of your bitcoin lightning channel is \(addSpacesToString(balanceValue:"\(actualChannel.size)")) satoshis. You've already purchased \(addSpacesToString(balanceValue:"\(actualChannel.received+actualChannel.punishmentReserve)")) sats, so you can still receive up to \(addSpacesToString(balanceValue:"\(actualChannel.size - actualChannel.received - actualChannel.punishmentReserve)")) sats in total.\n\nPer invoice you can receive up to ten percent of the channel size, so \(addSpacesToString(balanceValue:"\(actualChannel.receivableMaximum)")) sats. If you need more, you can create multiple invoices.\n\nWhen the channel is full, we empty the channel funds into your bitcoin wallet so that you have space again."
                } else {
                    self.headerLabel.text = "why can't I send instant payments?"
                    self.answerLabel.text = "To send and receive Bitcoin Lightning payments, you need to have at least one Lightning channel with anyone.\n\nTo open a channel with Bittr, buy bitcoin worth up to 100 Swiss Francs or Euros. Check your wallet's Buy section or getbittr.com for all information."
                }
            } else if actualType == "lightningsendable" {
                if let actualChannel = bittrChannel {
                    
                    self.setChannelChart()
                    
                    self.answerLabel.text = "Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning channel (for instant payments).\n\nYou've already purchased \(addSpacesToString(balanceValue:"\(actualChannel.received+actualChannel.punishmentReserve)")) satoshis into your lightning channel. Your channel needs to contain a minimum of \(addSpacesToString(balanceValue:"\(actualChannel.punishmentReserve)")) sats, so the maximum amount you can send in total is \(addSpacesToString(balanceValue:"\(actualChannel.received)")) sats.\n\nPer invoice you can send up to ten percent of the channel size. The size of your channel is \(addSpacesToString(balanceValue:"\(actualChannel.size)")) sats, so per invoice you can send up to \(addSpacesToString(balanceValue:"\(actualChannel.receivableMaximum)")) sats." //\n\nThe minimum amount of satoshis you can send per invoice is \(addSpacesToString(balanceValue:"\(actualChannel.sendableMinimum)")) sats."
                } else {
                    self.headerLabel.text = "why can't I receive instant payments?"
                    self.answerLabel.text = "Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning channel (for instant payments).\n\nYou don't currently have a lightning channel.\n\nTo open a channel with Bittr, buy bitcoin worth up to 100 Swiss Francs or Euros. Check your wallet's Buy section or getbittr.com for all information."
                }
            } else if actualType == "lightningexplanation" {
                if let actualChannel = bittrChannel {
                    
                    self.setChannelChart()
                    
                    self.answerLabel.text = "Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning channel (for instant payments).\n\nYou've already purchased \(addSpacesToString(balanceValue:"\(actualChannel.received+actualChannel.punishmentReserve)")) satoshis into your lightning channel. The size of your channel is \(addSpacesToString(balanceValue:"\(actualChannel.size)")) sats, so you can still purchase another \(addSpacesToString(balanceValue:"\(actualChannel.size - actualChannel.received - actualChannel.punishmentReserve)")) sats.\n\nWhen the channel is full, we empty its funds into your bitcoin wallet so that you have space again."
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
        
        self.yourBalanceLabel.text = "\(addSpacesToString(balanceValue: "\(bittrChannel!.received+bittrChannel!.punishmentReserve)"))"
        self.receiveLimitLabel.text = "\(addSpacesToString(balanceValue: "\(bittrChannel!.size - bittrChannel!.received - bittrChannel!.punishmentReserve)"))"
        self.totalLabel.text = "\(addSpacesToString(balanceValue: "\(bittrChannel!.size)")) total, \(addSpacesToString(balanceValue: "\(bittrChannel!.punishmentReserve)")) reserve"
        
        NSLayoutConstraint.deactivate([self.balanceBarWidth])
        self.balanceBarWidth = NSLayoutConstraint(item: self.balanceBar, attribute: .width, relatedBy: .equal, toItem: self.barView, attribute: .width, multiplier: CGFloat(bittrChannel!.received+bittrChannel!.punishmentReserve)/CGFloat(bittrChannel!.size), constant: 0)
        NSLayoutConstraint.activate([self.balanceBarWidth])
        self.answerLabelBottom.constant = 140
        self.view.layoutIfNeeded()
        
        self.channelView.alpha = 1
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor(color: "yellowandgrey")
        self.answerLabel.textColor = Colors.getColor(color: "black")
        
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
