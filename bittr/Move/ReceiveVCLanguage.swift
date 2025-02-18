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
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        
        // Switch
        self.switchView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.switchSelectionView.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelRegular.textColor = Colors.getColor("blackorwhite")
        self.labelInstant.textColor = Colors.getColor("blackorwhite")
        self.iconLightning.tintColor = Colors.getColor("blackorwhite")
        
        // QR scanner
        self.qrScannerView.backgroundColor = Colors.getColor("yelloworblue1")
        
        // Regular
        self.addressView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.addressLabel.textColor = Colors.getColor("blackorwhite")
        self.addressSpinner.color = Colors.getColor("blackorwhite")
        self.addressCopy.tintColor = Colors.getColor("blackorwhite")
        
        // Subtitle
        self.subtitleRegular.textColor = Colors.getColor("blackorwhite")
        self.subtitleInstant.textColor = Colors.getColor("blackorwhite")
        
        // Instant
        self.amountLabel.textColor = Colors.getColor("blackoryellow")
        self.descriptionLabel.textColor = Colors.getColor("blackoryellow")
        self.receivableLNLabel.textColor = Colors.getColor("blackorwhite")
        self.questionCircle.tintColor = Colors.getColor("blackorwhite")
        self.amountView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.descriptionView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.amountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteramount"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.amountTextField.textColor = Colors.getColor("blackorwhite")
        self.descriptionTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enterdescription"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.descriptionTextField.textColor = Colors.getColor("blackorwhite")
        self.lnurlQrView.backgroundColor = Colors.getColor("whiteorblue3")
        self.scanQrImage.tintColor = Colors.getColor("blackorwhite")
        
        // Instant confirmation
        self.lnConfirmationLabel.textColor = Colors.getColor("blackorwhite")
        self.qrScannerLabel.textColor = Colors.getColor("blackorwhite")
        self.lnConfirmationAddressView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.lnInvoiceLabel.textColor = Colors.getColor("blackorwhite")
        self.lnInvoiceCopy.tintColor = Colors.getColor("blackorwhite")
    }
}
