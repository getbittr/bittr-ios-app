//
//  HomeHeaderTableViewCell.swift
//  bittr
//
//  Created by Tom Melters on 9/8/26.
//

import UIKit

class HomeHeaderTableViewCell: UITableViewCell {
    
    // Balance card
    @IBOutlet weak var balanceCard: UIView!
    @IBOutlet weak var balanceCardTop: NSLayoutConstraint!
    @IBOutlet weak var balanceCardButton: UIButton!
    @IBOutlet weak var bottomCurve: BottomCurveView!
    @IBOutlet weak var noTransactionsLabel: UILabel!
    
    // Header
    @IBOutlet weak var headerSpinner: UIActivityIndicatorView!
    @IBOutlet weak var headerPiggyImage: UIImageView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var headerProblemImage: UIImageView!
    @IBOutlet weak var headerDetailsImage: UIImageView!
    @IBOutlet weak var syncButton: UIButton!
    @IBOutlet weak var currencyButton: UIButton!
    @IBOutlet weak var mapButton: UIButton!
    
    // Balance
    @IBOutlet weak var balanceView: UIView!
    @IBOutlet weak var bitcoinSign: UIImageView!
    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var balanceLabelWidth: NSLayoutConstraint!
    
    // Conversion
    @IBOutlet weak var conversionLabel: UILabel!
    
    // Profit
    @IBOutlet weak var profitView: UIView!
    @IBOutlet weak var profitArrow: UIImageView!
    @IBOutlet weak var profitLabel: UILabel!
    @IBOutlet weak var profitButton: UIButton!
    
    // Send/Receive/Buy buttons
    @IBOutlet weak var sendView: UIView!
    @IBOutlet weak var receiveView: UIView!
    @IBOutlet weak var buyView: UIView!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var receiveButton: UIButton!
    @IBOutlet weak var buyButton: UIButton!
    @IBOutlet weak var sendLabel: UILabel!
    @IBOutlet weak var receiveLabel: UILabel!
    @IBOutlet weak var buyLabel: UILabel!
    
    // Conversion and Map
    @IBOutlet weak var conversionCard: UIView!
    @IBOutlet weak var conversionGraph: GraphView!
    @IBOutlet weak var mapCard: UIView!
    @IBOutlet weak var headerCurrencyImage: UIImageView!
    @IBOutlet weak var headerMapImage: UIImageView!
    @IBOutlet weak var headerCurrencyLabel: UILabel!
    @IBOutlet weak var headerMapLabel: UILabel!
    
    // Variables
    var homeVC:HomeViewController?
    var appliedNoTransactionsHTML:String?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        // Update basic styling and colors.
        self.changeColors()
        self.setWords()
        self.setStyling()
    }
    
    func setStyling() {
        
        // Corner radii
        self.balanceCard.layer.cornerRadius = 13
        self.profitView.layer.cornerRadius = 13
        self.sendView.layer.cornerRadius = 8
        self.receiveView.layer.cornerRadius = 8
        self.buyView.layer.cornerRadius = 8
        self.conversionCard.layer.cornerRadius = 13
        self.mapCard.layer.cornerRadius = 13
        
        // Button titles
        self.balanceCardButton.setTitle("", for: .normal)
        self.sendButton.setTitle("", for: .normal)
        self.receiveButton.setTitle("", for: .normal)
        self.buyButton.setTitle("", for: .normal)
        self.profitButton.setTitle("", for: .normal)
        self.syncButton.setTitle("", for: .normal)
        self.currencyButton.setTitle("", for: .normal)
        self.mapButton.setTitle("", for: .normal)
        
        // Styling
        self.balanceCard.setShadow()
        self.sendView.setShadow()
        self.receiveView.setShadow()
        self.buyView.setShadow()
        self.conversionCard.setShadow()
        self.mapCard.setShadow()
        
        // Accessibility identifiers
        self.headerSpinner.accessibilityIdentifier = TestID.Home.headerSpinner
        self.headerLabel.accessibilityIdentifier = TestID.Home.headerLabel
        self.balanceLabel.accessibilityIdentifier = TestID.Home.balanceLabel
        self.profitLabel.accessibilityIdentifier = TestID.Home.profitLabel
        self.balanceCardButton.accessibilityIdentifier = TestID.Home.balanceCardButton
        self.sendButton.accessibilityIdentifier = TestID.Home.sendButton
        self.receiveButton.accessibilityIdentifier = TestID.Home.receiveButton
        self.buyButton.accessibilityIdentifier = TestID.Home.buyButton
        self.profitButton.accessibilityIdentifier = TestID.Home.profitButton
        self.syncButton.accessibilityIdentifier = TestID.Home.syncStatusButton
        self.currencyButton.accessibilityIdentifier = TestID.Home.currencyButton
        self.mapButton.accessibilityIdentifier = TestID.Home.mapButton
        
        // Accessibility labels
        self.balanceCardButton.accessibilityLabel = "Balance details"
        self.sendButton.accessibilityLabel = Language.getWord(withID: "send")
        self.receiveButton.accessibilityLabel = Language.getWord(withID: "receive")
        self.buyButton.accessibilityLabel = Language.getWord(withID: "buy")
    }
    
    @objc func setWords() {
        
        // Words
        self.headerLabel.text = Language.getWord(withID: "yourwallet")
        self.sendLabel.text = Language.getWord(withID: "send")
        self.receiveLabel.text = Language.getWord(withID: "receive")
        self.buyLabel.text = Language.getWord(withID: "buy")
        self.headerCurrencyLabel.text = Language.getWord(withID: "homevcvalue")
        self.headerMapLabel.text = Language.getWord(withID: "homevcmap")
    }
    
    @objc func changeColors() {
        
        // Colors
        self.contentView.backgroundColor = Colors.getColor("yelloworblue3")
        self.headerSpinner.color = Colors.getColor("whiteoryellow")
        self.balanceCard.backgroundColor = Colors.getColor("yelloworblue3")
        self.conversionCard.backgroundColor = Colors.getColor("yelloworblue3")
        self.mapCard.backgroundColor = Colors.getColor("yelloworblue3")
        self.headerPiggyImage.image = UIImage(named: CacheManager.darkModeIsOn() ? "iconpiggyyellow" : "iconpiggywhite")
        self.headerLabel.textColor = Colors.getColor("whiteoryellow")
        self.headerCurrencyLabel.textColor = Colors.getColor("whiteoryellow")
        self.headerMapLabel.textColor = Colors.getColor("whiteoryellow")
        self.headerDetailsImage.image = UIImage(named: CacheManager.darkModeIsOn() ? "icondetailsyellow" : "icondetailswhite")
        self.headerCurrencyImage.image = UIImage(named: CacheManager.darkModeIsOn() ? "iconexchangeyellow" : "iconexchange")
        self.headerMapImage.image = UIImage(named: CacheManager.darkModeIsOn() ? "iconmapyellow" : "iconmapwhite")
        self.bitcoinSign.image = UIImage(named: CacheManager.darkModeIsOn() ? "gilroybitcoinwhite" : "gilroybitcoin")
        self.conversionGraph.setNeedsDisplay()
        self.conversionLabel.textColor = CacheManager.darkModeIsOn() ? UIColor(red: 170/255, green: 190/255, blue: 217/255, alpha: 1) : UIColor(red: 201/255, green: 154/255, blue: 0/255, alpha: 1)
        self.sendView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.receiveView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.buyView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.sendLabel.textColor = Colors.getColor("blackorwhite")
        self.receiveLabel.textColor = Colors.getColor("blackorwhite")
        self.buyLabel.textColor = Colors.getColor("blackorwhite")
        self.bottomCurve.fillColor = Colors.getColor("yelloworblue3")
        
        if self.profitArrow.image == UIImage(systemName: "arrow.down") {
            // Loss
            self.profitLabel.textColor = Colors.getColor("losstext")
            self.profitView.backgroundColor = Colors.getColor("lossbackground0.8")
            self.profitArrow.tintColor = Colors.getColor("losstext")
        } else {
            // Profit
            self.profitLabel.textColor = Colors.getColor("profittext")
            self.profitView.backgroundColor = Colors.getColor("profitbackground0.8")
            self.profitArrow.tintColor = Colors.getColor("profittext")
        }
        
        self.updateNoTransactionsLabel()
    }
    
    func updateNoTransactionsLabel() {
        
        let textColor = CacheManager.darkModeIsOn() ? "255, 255, 255" : "177, 177, 177"
        
        let noTransactionsHTML = "<center><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16; color: rgb(\(textColor)); line-height: 1.2\">\(Language.getWord(withID: "notransactions1"))</span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: 16; color: rgb(\(textColor)); line-height: 1.2\">\(Language.getWord(withID: "buy"))</span><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16; color: rgb(\(textColor)); line-height: 1.2\">\(Language.getWord(withID:"notransactions2"))</span></center>"
        
        guard noTransactionsHTML != self.appliedNoTransactionsHTML else { return }
        self.appliedNoTransactionsHTML = noTransactionsHTML
        
        if let htmlData = noTransactionsHTML.data(using: .unicode) {
            do {
                let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                self.noTransactionsLabel.attributedText = attributedText
            } catch {
                Log.info("Couldn't fetch text: \(error.localizedDescription)")
                SentryManager.capture(error, context: "LoadWalletData row 489")
            }
        }
    }
    
    func updateLayout(topSafeArea: CGFloat) {
        self.balanceCardTop.constant = topSafeArea + 75
    }
}
