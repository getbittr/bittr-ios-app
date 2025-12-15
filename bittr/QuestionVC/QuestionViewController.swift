//
//  QuestionViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/02/2024.
//

import UIKit
import LDKNode

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
        self.downButton.setTitle("", for: .normal)
        self.headerView.layer.cornerRadius = 13
        self.channelView.layer.cornerRadius = 13
        self.barView.layer.cornerRadius = 2
        
        // Channel view shadow
        self.channelView.setShadow()
        
        if let actualHeader = headerText, let actualAnswer = answerText {
            self.headerLabel.text = actualHeader
            self.answerLabel.text = actualAnswer
        }
        
        self.changeColors()
        
        if let actualType = self.questionType {
            
            // Get active channel.
            let activeChannel = self.coreVC!.bittrWallet.lightningChannels.getActiveChannel()
            
            if activeChannel != nil {
                self.setChannelChart(forChannel: activeChannel!)
                
                if actualType == "lightningreceivable" {
                    self.answerLabel.text = Language.getWord(withID: "questionvc1")
                        .replacingOccurrences(of: "<channelsize>", with: "\(activeChannel!.channelValueSats)".addSpaces())
                        .replacingOccurrences(of: "<channelbalance>", with: "\((activeChannel!.outboundCapacityMsat/1000)+(activeChannel!.unspendablePunishmentReserve ?? 0))".addSpaces())
                        .replacingOccurrences(of: "<receivelimit>", with: "\(activeChannel!.channelValueSats - (activeChannel!.outboundCapacityMsat/1000) - (activeChannel!.unspendablePunishmentReserve ?? 0))".addSpaces())
                } else if actualType == "lightningsendable" {
                    self.answerLabel.text = Language.getWord(withID: "questionvc7")
                        .replacingOccurrences(of: "<channelbalance>", with: "\((activeChannel!.outboundCapacityMsat/1000)+(activeChannel!.unspendablePunishmentReserve ?? 0))".addSpaces())
                        .replacingOccurrences(of: "<channelreserve>", with: "\(activeChannel!.unspendablePunishmentReserve ?? 0)".addSpaces())
                        .replacingOccurrences(of: "<sendlimit>", with: "\(activeChannel!.outboundCapacityMsat/1000)".addSpaces())
                } else if actualType == "lightningexplanation" {
                    self.answerLabel.text = Language.getWord(withID: "questionvc7")
                        .replacingOccurrences(of: "<channelbalance>", with: "\((activeChannel!.outboundCapacityMsat/1000)+(activeChannel!.unspendablePunishmentReserve ?? 0))".addSpaces())
                        .replacingOccurrences(of: "<channelreserve>", with: "\(activeChannel!.unspendablePunishmentReserve ?? 0)".addSpaces())
                        .replacingOccurrences(of: "<sendlimit>", with: "\(activeChannel!.outboundCapacityMsat/1000)".addSpaces())
                }
            } else {
                if actualType == "lightningreceivable" {
                    self.headerLabel.text = Language.getWord(withID: "questionvc6")
                    self.answerLabel.text = Language.getWord(withID: "lightningexplanation1")
                } else if actualType == "lightningsendable" {
                    self.headerLabel.text = Language.getWord(withID: "questionvc12")
                    self.answerLabel.text = Language.getWord(withID: "questionvc13")
                }
            }
        }
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
