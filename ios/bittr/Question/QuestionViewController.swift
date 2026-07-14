//
//  QuestionViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/02/2024.
//

import UIKit
import LDKNode

class QuestionViewController: UIViewController {

    // Generic items
    @IBOutlet weak var yellowCard: UIView!
    
    // Labels
    @IBOutlet weak var answerLabel: UILabel!
    
    // Channel chart
    @IBOutlet weak var channelStack: UIView!
    @IBOutlet weak var channelStackHeight: NSLayoutConstraint!
    @IBOutlet weak var channelView: UIView!
    @IBOutlet weak var yourBalanceTitle: UILabel!
    @IBOutlet weak var yourBalanceLabel: UILabel!
    @IBOutlet weak var receiveLimitTitle: UILabel!
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

        self.yellowCard.accessibilityIdentifier = TestID.Question.yellowCard
        self.answerLabel.accessibilityIdentifier = TestID.Question.answerLabel
        self.channelView.accessibilityIdentifier = TestID.Question.channelView

        // Corner radii and button titles
        self.yellowCard.layer.cornerRadius = 13
        self.channelView.layer.cornerRadius = 8
        self.barView.layer.cornerRadius = 2
        
        // Channel view shadow
        self.channelView.setShadow()
        self.yellowCard.setShadow()
        
        self.changeColors()
        self.answerLabel.text = self.answerText ?? ""
        var topHeaderText = self.headerText ?? ""
        
        if let actualType = self.questionType {
            
            // Get active channel.
            let activeChannel = BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel()
            
            if activeChannel != nil {
                self.setChannelChart(forChannel: activeChannel!)
                
                if actualType == "lightningreceivable" {
                    self.answerLabel.attributedText = Language.getWord(withID: "questionvc1")
                        .replacingOccurrences(of: "<channelsize>", with: "\(activeChannel!.channelValueSats)".addSpaces())
                        .replacingOccurrences(of: "<channelbalance>", with: "\((activeChannel!.outboundCapacityMsat/1000)+(activeChannel!.unspendablePunishmentReserve ?? 0))".addSpaces())
                        .replacingOccurrences(of: "<receivelimit>", with: "\(activeChannel!.channelValueSats - (activeChannel!.outboundCapacityMsat/1000) - (activeChannel!.unspendablePunishmentReserve ?? 0))".addSpaces()).attributed()
                } else if actualType == "lightningsendable" {
                    self.answerLabel.attributedText = Language.getWord(withID: "questionvc7")
                        .replacingOccurrences(of: "<channelbalance>", with: "\((activeChannel!.outboundCapacityMsat/1000)+(activeChannel!.unspendablePunishmentReserve ?? 0))".addSpaces())
                        .replacingOccurrences(of: "<channelreserve>", with: "\(activeChannel!.unspendablePunishmentReserve ?? 0)".addSpaces())
                        .replacingOccurrences(of: "<sendlimit>", with: "\(activeChannel!.outboundCapacityMsat/1000)".addSpaces()).attributed()
                } else if actualType == "lightningexplanation" {
                    self.answerLabel.attributedText = Language.getWord(withID: "questionvc7")
                        .replacingOccurrences(of: "<channelbalance>", with: "\((activeChannel!.outboundCapacityMsat/1000)+(activeChannel!.unspendablePunishmentReserve ?? 0))".addSpaces())
                        .replacingOccurrences(of: "<channelreserve>", with: "\(activeChannel!.unspendablePunishmentReserve ?? 0)".addSpaces())
                        .replacingOccurrences(of: "<sendlimit>", with: "\(activeChannel!.outboundCapacityMsat/1000)".addSpaces()).attributed()
                }
            } else {
                if actualType == "lightningreceivable" {
                    topHeaderText = Language.getWord(withID: "questionvc6")
                    self.answerLabel.attributedText = Language.getWord(withID: "lightningexplanation1").attributed()
                } else if actualType == "lightningsendable" {
                    topHeaderText = Language.getWord(withID: "questionvc12")
                    self.answerLabel.attributedText = Language.getWord(withID: "questionvc13").attributed()
                }
            }
        }
        
        // Add header
        self.addHeader(iconLight: "iconpiggywhite", iconDark: "iconpiggyyellow", title: topHeaderText)
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func setChannelChart(forChannel:ChannelDetails) {
        
        self.yourBalanceLabel.text = "\("\((forChannel.outboundCapacityMsat/1000)+(forChannel.unspendablePunishmentReserve ?? 0))".addSpaces())"
        self.receiveLimitLabel.text = "\("\(forChannel.channelValueSats - (forChannel.outboundCapacityMsat/1000) - (forChannel.unspendablePunishmentReserve ?? 0))".addSpaces())"
        self.totalLabel.text = "\("\(forChannel.channelValueSats)".addSpaces()) \(Language.getWord(withID: "total")), \("\(forChannel.unspendablePunishmentReserve ?? 0)".addSpaces()) \(Language.getWord(withID: "reserve"))"
        
        NSLayoutConstraint.deactivate([self.balanceBarWidth])
        self.balanceBarWidth = NSLayoutConstraint(item: self.balanceBar, attribute: .width, relatedBy: .equal, toItem: self.barView, attribute: .width, multiplier: CGFloat((forChannel.outboundCapacityMsat/1000)+(forChannel.unspendablePunishmentReserve ?? 0))/CGFloat(forChannel.channelValueSats), constant: 0)
        NSLayoutConstraint.activate([self.balanceBarWidth])
        self.channelStackHeight.constant = 20 + self.channelView.frame.height
        self.channelStack.alpha = 1
        self.view.layoutIfNeeded()
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
        self.channelView.backgroundColor = Colors.getColor("whiteorblue3")
        self.yourBalanceTitle.textColor = Colors.getColor("blackoryellow")
        self.receiveLimitTitle.textColor = Colors.getColor("blackoryellow")
        self.yourBalanceLabel.textColor = Colors.getColor("blackorwhite")
        self.receiveLimitLabel.textColor = Colors.getColor("blackorwhite")
        self.totalLabel.textColor = Colors.getColor("blackorwhite")
        self.answerLabel.textColor = Colors.getColor("blackorwhite")
    }
    
}

extension [ChannelDetails] {
    
    func getActiveChannel() -> ChannelDetails? {
        
        for eachChannel in self {
            if eachChannel.isChannelReady {
                    return eachChannel
            }
        }
        return nil
    }
}
