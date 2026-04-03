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
        self.btcView.layer.cornerRadius = 8
        self.btcView.setShadow()
        self.bothAmountView.layer.cornerRadius = 8
        self.bothDescriptionView.layer.cornerRadius = 8
        
        // Button titles
        self.contentBackgroundButton.setTitle("", for: .normal)
        self.btcButton.setTitle("", for: .normal)
    }
    
    func setWords() {
        
        //self.addressTitle.text = Language.getWord(withID: "url")
        
        /*self.labelRegular.text = Language.getWord(withID: "regular")
        self.labelBoth.text = Language.getWord(withID: "both")
        self.labelInstant.text = Language.getWord(withID: "instant")
        self.labelUrl.text = Language.getWord(withID: "url")
        self.bothAmountTextField.placeholder = Language.getWord(withID: "insatoshis")
        self.bothAmountLabel.text = Language.getWord(withID: "bothamountlabel")*/
        
    }
    
    func changeColors() {
        
        // Generic
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
        self.addressView.backgroundColor = Colors.getColor("whiteorblue3")
        self.addressLabel.textColor = Colors.getColor("blackorwhite")
        self.btcView.backgroundColor = Colors.getColor("whiteorblue3")
        self.btcLabel.textColor = Colors.getColor("blackorwhite")
        
        // Instant
        self.bothAmountLabel.textColor = Colors.getColor("blackoryellow")
        self.bothAmountView.backgroundColor = Colors.getColor("white0.7orblue1")
        self.bothDescriptionView.backgroundColor = Colors.getColor("white0.7orblue1")
        self.bothAmountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "amountinsatoshis"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.bothDescriptionTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "description"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.bothAmountTextField.textColor = Colors.getColor("blackorwhite")
    }
}
