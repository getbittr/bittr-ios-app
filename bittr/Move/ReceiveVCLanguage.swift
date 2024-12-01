//
//  ReceiveVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 10/10/2024.
//

import UIKit

extension ReceiveViewController {
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "receivebitcoin")
        self.labelRegular.text = Language.getWord(withID: "regular")
        self.labelInstant.text = Language.getWord(withID: "instant")
        self.subtitleRegular.text = Language.getWord(withID: "thisisanaddress")
        self.subtitleInstant.text = Language.getWord(withID: "createaninvoice")
        self.amountLabel.text = Language.getWord(withID: "amountinsatoshis")
        self.descriptionLabel.text = Language.getWord(withID: "description")
        self.amountTextField.placeholder = Language.getWord(withID: "enteramount")
        self.descriptionTextField.placeholder = Language.getWord(withID: "enterdescription")
        self.createInvoiceLabel.text = Language.getWord(withID: "createinvoice")
        self.lnHeaderLabel.text = Language.getWord(withID: "lightninginvoice")
        self.lnConfirmationLabel.text = Language.getWord(withID: "thisisyourinvoice")
        self.lnDoneLabel.text = Language.getWord(withID: "done")
        self.qrScannerLabel.text = Language.getWord(withID: "lnurlscannerlabel")
        self.qrScannerCloseLabel.text = Language.getWord(withID: "close")
        
    }
    
    func changeColors() {
        
        // View
        self.view.backgroundColor = Colors.getColor(color: "yellowandgrey")
        
        // Switch
        self.switchView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.switchSelectionView.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.labelRegular.textColor = Colors.getColor(color: "blackorwhite")
        self.labelInstant.textColor = Colors.getColor(color: "blackorwhite")
        self.iconLightning.tintColor = Colors.getColor(color: "blackorwhite")
        
        // QR scanner
        self.qrScannerView.backgroundColor = Colors.getColor(color: "yellowandgrey")
        
        // Regular
        self.addressView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.addressLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.addressSpinner.color = Colors.getColor(color: "blackorwhite")
        self.addressCopy.tintColor = Colors.getColor(color: "blackorwhite")
        
        // Subtitle
        self.subtitleRegular.textColor = Colors.getColor(color: "blackorwhite")
        self.subtitleInstant.textColor = Colors.getColor(color: "blackorwhite")
        
        // Instant
        self.amountLabel.textColor = Colors.getColor(color: "blackoryellow")
        self.descriptionLabel.textColor = Colors.getColor(color: "blackoryellow")
        self.receivableLNLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.questionCircle.tintColor = Colors.getColor(color: "blackorwhite")
        self.amountView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.descriptionView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.amountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteramount"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor(color: "grey2orwhite0.7")]
        )
        self.amountTextField.textColor = Colors.getColor(color: "blackorwhite")
        self.descriptionTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enterdescription"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor(color: "grey2orwhite0.7")]
        )
        self.descriptionTextField.textColor = Colors.getColor(color: "blackorwhite")
        self.lnurlQrView.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.scanQrImage.tintColor = Colors.getColor(color: "blackorwhite")
        
        // Instant confirmation
        self.lnConfirmationLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.qrScannerLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.lnConfirmationAddressView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.lnInvoiceLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.lnInvoiceCopy.tintColor = Colors.getColor(color: "blackorwhite")
    }
}
