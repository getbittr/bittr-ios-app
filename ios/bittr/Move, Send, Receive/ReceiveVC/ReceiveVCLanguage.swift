//
//  ReceiveVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 10/10/2024.
//

import UIKit

extension ReceiveViewController {
    
    func setBasicStyling() {
        
        // Generic
        self.yellowCard.layer.cornerRadius = 13
        self.yellowCard.setShadow()
        self.qrWhiteView.layer.cornerRadius = 8
        self.qrWhiteView.setShadow()
        self.addressView.layer.cornerRadius = 8
        self.addressView.setShadow()
        
        // Cards
        self.copyCard.layer.cornerRadius = 8
        self.copyCard.setShadow()
        self.refreshCard.layer.cornerRadius = 8
        self.refreshCard.setShadow()
        self.editCard.layer.cornerRadius = 8
        self.editCard.setShadow()
        self.moreCard.layer.cornerRadius = 8
        self.moreCard.setShadow()
        
        // Amount and description
        self.btcView.layer.cornerRadius = 8
        self.btcView.setShadow()
        self.bothAmountView.layer.cornerRadius = 8
        self.bothDescriptionView.layer.cornerRadius = 8
        
        // Button titles
        self.contentBackgroundButton.setTitle("", for: .normal)
        self.btcButton.setTitle("", for: .normal)
        self.copyButton.setTitle("", for: .normal)
        self.refreshButton.setTitle("", for: .normal)
        self.editButton.setTitle("", for: .normal)
        self.moreButton.setTitle("", for: .normal)
        self.addressViewButton.setTitle("", for: .normal)
        self.questionButton.setTitle("", for: .normal)
    }
    
    func setWords() {
        
        self.copyLabel.text = Language.getWord(withID: "copy")
        self.refreshLabel.text = Language.getWord(withID: "refresh")
        self.editLabel.text = Language.getWord(withID: "receiveamount")
        self.moreLabel.text = Language.getWord(withID: "more")
        
    }
    
    func changeColors() {
        
        // Generic
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
        self.addressView.backgroundColor = Colors.getColor("whiteorblue3")
        self.addressLabel.textColor = Colors.getColor("blackorwhite")
        self.lowerAddressLabel.textColor = Colors.getColor("blackorwhite")
        self.btcView.backgroundColor = Colors.getColor("whiteorblue3")
        self.btcLabel.textColor = Colors.getColor("blackorwhite")
        
        // Cards
        self.copyCard.backgroundColor = Colors.getColor("white0.7orblue3")
        self.copyLabel.textColor = Colors.getColor("blackorwhite")
        self.copyIcon.tintColor = Colors.getColor("blackorwhite")
        self.refreshCard.backgroundColor = Colors.getColor("white0.7orblue3")
        self.refreshLabel.textColor = Colors.getColor("blackorwhite")
        self.refreshIcon.tintColor = Colors.getColor("blackorwhite")
        self.editCard.backgroundColor = Colors.getColor("white0.7orblue3")
        self.editLabel.textColor = Colors.getColor("blackorwhite")
        self.editIcon.tintColor = Colors.getColor("blackorwhite")
        self.moreCard.backgroundColor = Colors.getColor("white0.7orblue3")
        self.moreLabel.textColor = Colors.getColor("blackorwhite")
        self.moreIcon.tintColor = Colors.getColor("blackorwhite")
        
        // Instant
        self.bothAmountView.backgroundColor = Colors.getColor("white0.7orblue1")
        self.bothDescriptionView.backgroundColor = Colors.getColor("white0.7orblue1")
        self.bothAmountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "receiveenteramount"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.bothDescriptionTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "receiveenterdescription"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.bothAmountTextField.textColor = Colors.getColor("blackorwhite")
    }
}
