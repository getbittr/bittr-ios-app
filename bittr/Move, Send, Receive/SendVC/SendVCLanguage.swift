//
//  SendVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension SendViewController {
    
    func setWords() {
        
        self.sendBitcoinLabel.text = Language.getWord(withID: "sendbitcoin")
        self.toLabel.text = Language.getWord(withID: "addressandamount")
        self.toTextField.placeholder = Language.getWord(withID: "enteraddress")
        self.labelRegular.text = Language.getWord(withID: "regular")
        self.labelInstant.text = Language.getWord(withID: "instant")
        self.amountTextField.placeholder = Language.getWord(withID: "enteramount")
        self.nextLabel.text = Language.getWord(withID: "next")
        self.confirmHeaderLabel.text = Language.getWord(withID: "confirmtransaction")
        self.confirmTopLabel.text = Language.getWord(withID: "checkdetails")
        self.labelAddress.text = Language.getWord(withID: "address")
        self.labelAmount.text = Language.getWord(withID: "amount")
        self.feesTopLabel.text = Language.getWord(withID: "feerate")
        self.sendLabel.text = Language.getWord(withID: "send")
        self.stackLabelQR.text = Language.getWord(withID: "sendvcscan")
        self.stackLabelPaste.text = Language.getWord(withID: "sendvcpaste")
        self.spinnerLabel.text = Language.getWord(withID: "handlinglnurl")
        
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        
        self.switchView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.switchSelectionView.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelRegular.textColor = Colors.getColor("blackorwhite")
        self.labelInstant.textColor = Colors.getColor("blackorwhite")
        self.iconLightning.tintColor = Colors.getColor("blackorwhite")
        
        self.toLabel.textColor = Colors.getColor("blackoryellow")
        self.backgroundQR.backgroundColor = Colors.getColor("whiteorblue3")
        self.backgroundPaste.backgroundColor = Colors.getColor("whiteorblue3")
        self.stackLabelQR.textColor = Colors.getColor("blackorwhite")
        self.stackLabelPaste.textColor = Colors.getColor("blackorwhite")
        self.stackImageQR.tintColor = Colors.getColor("blackorwhite")
        self.stackImagePaste.tintColor = Colors.getColor("blackorwhite")
        self.toView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.toTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteraddress"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.toTextField.textColor = Colors.getColor("blackorwhite")
        
        self.availableAmount.textColor = Colors.getColor("blackorwhite")
        self.questionCircle.tintColor = Colors.getColor("blackorwhite")
        self.btcView.backgroundColor = Colors.getColor("whiteorblue3")
        self.btcLabel.textColor = Colors.getColor("blackorwhite")
        self.amountView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.amountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteramount"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.amountTextField.textColor = Colors.getColor("blackorwhite")
        
        self.confirmTopLabel.textColor = Colors.getColor("blackorwhite")
        self.yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
        self.confirmToCard.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmAmountCard.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmAddressLabel.textColor = Colors.getColor("blackorwhite")
        self.confirmAmountLabel.textColor = Colors.getColor("blackorwhite")
        self.confirmEuroLabel.textColor = Colors.getColor("blackorwhite")
        
        self.feesTopLabel.textColor = Colors.getColor("blackorwhite")
        self.timeFast.textColor = Colors.getColor("blackoryellow")
        self.timeMedium.textColor = Colors.getColor("blackoryellow")
        self.timeSlow.textColor = Colors.getColor("blackoryellow")
        self.satsFast.textColor = Colors.getColor("blackorwhite")
        self.satsMedium.textColor = Colors.getColor("blackorwhite")
        self.satsSlow.textColor = Colors.getColor("blackorwhite")
        self.eurosFast.textColor = Colors.getColor("blackorwhite")
        self.eurosMedium.textColor = Colors.getColor("blackorwhite")
        self.eurosSlow.textColor = Colors.getColor("blackorwhite")
        self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.mediumView.backgroundColor = Colors.getColor("whiteorblue3")
        self.slowView.backgroundColor = Colors.getColor("white0.7orblue2")
    }
    
    func setBasicStyling() {
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        self.amountButton.setTitle("", for: .normal)
        self.availableButton.setTitle("", for: .normal)
        self.pasteButton.setTitle("", for: .normal)
        self.backgroundButton.setTitle("", for: .normal)
        self.centerBackgroundButton.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        self.editButton.setTitle("", for: .normal)
        self.sendButton.setTitle("", for: .normal)
        self.regularButton.setTitle("", for: .normal)
        self.instantButton.setTitle("", for: .normal)
        self.fastButton.setTitle("", for: .normal)
        self.mediumButton.setTitle("", for: .normal)
        self.slowButton.setTitle("", for: .normal)
        self.qrButton.setTitle("", for: .normal)
        self.toButton.setTitle("", for: .normal)
        self.btcButton.setTitle("", for: .normal)
        
        // Corner radii
        self.toView.layer.cornerRadius = 8
        self.amountView.layer.cornerRadius = 8
        self.nextView.layer.cornerRadius = 8
        self.confirmHeaderView.layer.cornerRadius = 13
        self.editView.layer.cornerRadius = 8
        self.sendView.layer.cornerRadius = 8
        self.switchView.layer.cornerRadius = 13
        self.switchSelectionView.layer.cornerRadius = 8
        self.scannerView.layer.cornerRadius = 13
        self.yellowCard.layer.cornerRadius = 20
        self.confirmToCard.layer.cornerRadius = 8
        self.confirmAmountCard.layer.cornerRadius = 8
        self.fastView.layer.cornerRadius = 8
        self.mediumView.layer.cornerRadius = 8
        self.slowView.layer.cornerRadius = 8
        self.backgroundQR.layer.cornerRadius = 8
        self.backgroundPaste.layer.cornerRadius = 8
        self.spinnerBox.layer.cornerRadius = 13
        self.btcView.layer.cornerRadius = 8
        
        // Shadows
        self.setShadows(forView: self.yellowCard)
        self.setShadows(forView: self.fastView)
        self.setShadows(forView: self.mediumView)
        self.setShadows(forView: self.slowView)
        self.setShadows(forView: self.backgroundQR)
        self.setShadows(forView: self.backgroundPaste)
        self.setShadows(forView: self.btcView)
        self.setShadows(forView: self.switchSelectionView)
    }
}
