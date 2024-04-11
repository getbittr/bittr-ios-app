//
//  QuestionViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/02/2024.
//

import UIKit

class QuestionViewController: UIViewController {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var answerLabel: UILabel!
    
    var headerText:String?
    var answerText:String?
    var questionType:String?
    
    var bittrChannel:Channel?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        
        if let actualHeader = headerText, let actualAnswer = answerText {
            self.headerLabel.text = actualHeader
            self.answerLabel.text = actualAnswer
        }
        
        if let actualType = questionType {
            if actualType == "lightningreceivable" {
                if let actualChannel = bittrChannel {
                    self.answerLabel.text = "There's a limit to the amount of satoshis you can receive per invoice.\n\nThe size of your Bitcoin Lightning channel is \(addSpacesToString(balanceValue:"\(actualChannel.size)")) satoshis. You've already purchased \(addSpacesToString(balanceValue:"\(actualChannel.received+actualChannel.punishmentReserve)")) sats, so you can still receive up to \(addSpacesToString(balanceValue:"\(actualChannel.size - actualChannel.received - actualChannel.punishmentReserve)")) sats in total.\n\nPer invoice you can receive up to ten percent of the channel size, so \(addSpacesToString(balanceValue:"\(actualChannel.receivableMaximum)")) sats. If you need more, you can create multiple invoices.\n\nWhen the channel is full, we empty the channel funds into your bitcoin wallet so that you have space again."
                } else {
                    self.headerLabel.text = "why can't I send instant payments?"
                    self.answerLabel.text = "To send and receive Bitcoin Lightning payments, you need to have at least one Lightning channel with anyone.\n\nTo open a channel with Bittr, buy bitcoin worth up to 100 Swiss Francs or Euros. Check your wallet's Buy section or getbittr.com for all information."
                }
            } else if actualType == "lightningsendable" {
                if let actualChannel = bittrChannel {
                    self.answerLabel.text = "Your bittr wallet consists of a Bitcoin wallet (for regular payments) and a Bitcoin Lightning channel (for instant payments).\n\nYou've already purchased \(addSpacesToString(balanceValue:"\(actualChannel.received+actualChannel.punishmentReserve)")) satoshis into your Lightning channel. Your channel needs to contain a minimum of \(addSpacesToString(balanceValue:"\(actualChannel.punishmentReserve)")) sats, so the maximum amount you can send is \(addSpacesToString(balanceValue:"\(actualChannel.received)")) sats.\n\nThe minimum amount of satoshis you can send per invoice is \(addSpacesToString(balanceValue:"\(actualChannel.sendableMinimum)")) sats."
                } else {
                    self.headerLabel.text = "why can't I receive instant payments?"
                    self.answerLabel.text = "Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning channel (for instant payments).\n\nYou don't currently have a lightning channel.\n\nTo open a channel with Bittr, buy bitcoin worth up to 100 Swiss Francs or Euros. Check your wallet's Buy section or getbittr.com for all information."
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
    
}
