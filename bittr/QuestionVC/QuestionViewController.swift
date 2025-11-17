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
                    
                    self.answerLabel.text = Language.getWord(withID: "questionvc1")
                        .replacingOccurrences(of: "<channelsize>", with: "\(actualChannel.size)".addSpaces())
                        .replacingOccurrences(of: "<channelbalance>", with: "\(actualChannel.received+actualChannel.punishmentReserve)".addSpaces())
                        .replacingOccurrences(of: "<receivelimit>", with: "\(actualChannel.size - actualChannel.received - actualChannel.punishmentReserve)".addSpaces())
                } else {
                    self.headerLabel.text = Language.getWord(withID: "questionvc6")
                    self.answerLabel.text = Language.getWord(withID: "lightningexplanation1")
                }
            } else if actualType == "lightningsendable" {
                if let actualChannel = self.coreVC?.bittrWallet.bittrChannel {
                    
                    self.setChannelChart()
                    
                    self.answerLabel.text = Language.getWord(withID: "questionvc7")
                        .replacingOccurrences(of: "<channelbalance>", with: "\(actualChannel.received+actualChannel.punishmentReserve)".addSpaces())
                        .replacingOccurrences(of: "<channelreserve>", with: "\(actualChannel.punishmentReserve)".addSpaces())
                        .replacingOccurrences(of: "<sendlimit>", with: "\(actualChannel.received)".addSpaces())
                } else {
                    self.headerLabel.text = Language.getWord(withID: "questionvc12")
                    self.answerLabel.text = Language.getWord(withID: "questionvc13")
                }
            } else if actualType == "lightningexplanation" {
                if let actualChannel = self.coreVC?.bittrWallet.bittrChannel {
                    
                    self.setChannelChart()
                    
                    self.answerLabel.text = Language.getWord(withID: "questionvc7")
                        .replacingOccurrences(of: "<channelbalance>", with: "\(actualChannel.received+actualChannel.punishmentReserve)".addSpaces())
                        .replacingOccurrences(of: "<channelreserve>", with: "\(actualChannel.punishmentReserve)".addSpaces())
                        .replacingOccurrences(of: "<sendlimit>", with: "\(actualChannel.received)".addSpaces())
                }
            }
        }
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    func setChannelChart() {
        
        let bittrChannel = self.coreVC?.bittrWallet.bittrChannel
        self.yourBalanceLabel.text = "\("\(bittrChannel!.received+bittrChannel!.punishmentReserve)".addSpaces())"
        self.receiveLimitLabel.text = "\("\(bittrChannel!.size - bittrChannel!.received - bittrChannel!.punishmentReserve)".addSpaces())"
        self.totalLabel.text = "\("\(bittrChannel!.size)".addSpaces()) \(Language.getWord(withID: "total")), \("\(bittrChannel!.punishmentReserve)".addSpaces()) \(Language.getWord(withID: "reserve"))"
        
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
