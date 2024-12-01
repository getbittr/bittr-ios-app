//
//  SendVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension SendViewController {
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "sendbitcoin")
        self.topLabel.text = Language.getWord(withID: "sendtoplabel")
        self.toLabel.text = Language.getWord(withID: "address")
        self.toTextField.placeholder = Language.getWord(withID: "enteraddress")
        self.amountLabel.text = Language.getWord(withID: "amount")
        self.labelRegular.text = Language.getWord(withID: "regular")
        self.labelInstant.text = Language.getWord(withID: "instant")
        self.amountTextField.placeholder = Language.getWord(withID: "enteramount")
        self.nextLabel.text = Language.getWord(withID: "next")
        self.confirmHeaderLabel.text = Language.getWord(withID: "confirmtransaction")
        self.confirmTopLabel.text = Language.getWord(withID: "checkdetails")
        self.labelAddress.text = Language.getWord(withID: "address")
        self.labelAmount.text = Language.getWord(withID: "amount")
        self.feesTopLabel.text = Language.getWord(withID: "feerate")
        self.labelEdit.text = "<   " + Language.getWord(withID: "edit")
        self.sendLabel.text = Language.getWord(withID: "send")
        self.stackLabelQR.text = Language.getWord(withID: "sendvcscan")
        self.stackLabelPaste.text = Language.getWord(withID: "sendvcpaste")
        self.stackLabelType.text = Language.getWord(withID: "sendvctype")
        
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor(color: "yelloworblue1")
        
        self.switchView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.switchSelectionView.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.labelRegular.textColor = Colors.getColor(color: "blackorwhite")
        self.labelInstant.textColor = Colors.getColor(color: "blackorwhite")
        self.iconLightning.tintColor = Colors.getColor(color: "blackorwhite")
        
        self.topLabel.textColor = Colors.getColor(color: "blackorwhite")
        
        self.toLabel.textColor = Colors.getColor(color: "blackoryellow")
        self.backgroundQR.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.backgroundPaste.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.backgroundKeyboard.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.stackLabelQR.textColor = Colors.getColor(color: "blackorwhite")
        self.stackLabelPaste.textColor = Colors.getColor(color: "blackorwhite")
        self.stackLabelType.textColor = Colors.getColor(color: "blackorwhite")
        self.stackImageQR.tintColor = Colors.getColor(color: "blackorwhite")
        self.stackImagePaste.tintColor = Colors.getColor(color: "blackorwhite")
        self.stackImageType.tintColor = Colors.getColor(color: "blackorwhite")
        self.toView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.toTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteramount"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor(color: "grey2orwhite0.7")]
        )
        
        self.amountLabel.textColor = Colors.getColor(color: "blackoryellow")
        self.availableAmount.textColor = Colors.getColor(color: "blackorwhite")
        self.questionCircle.tintColor = Colors.getColor(color: "blackorwhite")
        self.btcView.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.btcLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.amountView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.amountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteraddress"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor(color: "grey2orwhite0.7")]
        )
        
        self.confirmTopLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.yellowCard.backgroundColor = Colors.getColor(color: "yelloworblue2")
        self.confirmToCard.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.confirmAmountCard.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.confirmAddressLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.confirmAmountLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.confirmEuroLabel.textColor = Colors.getColor(color: "blackorwhite")
        
        self.feesTopLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.timeFast.textColor = Colors.getColor(color: "blackoryellow")
        self.timeMedium.textColor = Colors.getColor(color: "blackoryellow")
        self.timeSlow.textColor = Colors.getColor(color: "blackoryellow")
        self.satsFast.textColor = Colors.getColor(color: "blackorwhite")
        self.satsMedium.textColor = Colors.getColor(color: "blackorwhite")
        self.satsSlow.textColor = Colors.getColor(color: "blackorwhite")
        self.eurosFast.textColor = Colors.getColor(color: "blackorwhite")
        self.eurosMedium.textColor = Colors.getColor(color: "blackorwhite")
        self.eurosSlow.textColor = Colors.getColor(color: "blackorwhite")
        self.fastView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.mediumView.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.slowView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        
        
        self.editView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.labelEdit.textColor = Colors.getColor(color: "blackorwhite")
    }
}
