//
//  ReceiveVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 10/10/2024.
//

import UIKit

extension ReceiveViewController {
    
    func setWords() {
        
        self.topLabel.text = Language.getWord(withID: "receivebitcoin")
        self.labelRegular.text = Language.getWord(withID: "regular")
        self.labelBoth.text = Language.getWord(withID: "both")
        self.labelInstant.text = Language.getWord(withID: "instant")
        self.subtitleRegular.text = Language.getWord(withID: "thisisanaddress")
        self.subtitleBoth.text = Language.getWord(withID: "subtitleboth")
        self.bothAmountTextField.placeholder = Language.getWord(withID: "insatoshis")
        self.createInvoiceLabel.text = Language.getWord(withID: "createinvoice")
        self.qrScannerLabel.text = Language.getWord(withID: "lnurlscannerlabel")
        self.qrScannerCloseLabel.text = Language.getWord(withID: "close")
        // Check if lightning address username is available
        if let coreVC = self.coreVC,
           let firstIban = coreVC.bittrWallet.ibanEntities.first,
           !firstIban.lightningAddressUsername.isEmpty {
            self.bothAmountLabel.text = firstIban.lightningAddressUsername
        } else {
            self.bothAmountLabel.text = Language.getWord(withID: "bothamountlabel")
        }
        self.spinnerLabel.text = Language.getWord(withID: "handlinglnurl")
        
    }
    
    func changeColors() {
        
        // View
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        
        // Switch
        self.viewRegular.backgroundColor = Colors.getColor("white0.7orblue2")
        self.viewBoth.backgroundColor = Colors.getColor("whiteorblue3")
        self.viewInstant.backgroundColor = Colors.getColor("white0.7orblue2")
        self.labelRegular.textColor = Colors.getColor("blackorwhite")
        self.labelInstant.textColor = Colors.getColor("blackorwhite")
        self.labelBoth.textColor = Colors.getColor("blackorwhite")
        self.iconLightning.tintColor = Colors.getColor("blackorwhite")
        
        // QR scanner
        self.qrScannerView.backgroundColor = Colors.getColor("yelloworblue1")
        
        // Regular
        self.addressView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.bothAddressView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.addressLabel.textColor = Colors.getColor("blackorwhite")
        self.bothAddressLabel.textColor = Colors.getColor("blackorwhite")
        self.addressSpinner.color = Colors.getColor("blackorwhite")
        self.addressCopy.tintColor = Colors.getColor("blackorwhite")
        self.bothAddressCopy.tintColor = Colors.getColor("blackorwhite")
        
        // Subtitle
        self.subtitleRegular.textColor = Colors.getColor("blackorwhite")
        
        // Instant
        self.bothAmountLabel.textColor = Colors.getColor("blackoryellow")
        self.bothAmountView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.bothDescriptionView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.bothAmountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "amountinsatoshis"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.bothDescriptionTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "description"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.bothAmountTextField.textColor = Colors.getColor("blackorwhite")
        self.lnurlQrView.backgroundColor = Colors.getColor("whiteorblue3")
        self.scanQrImage.tintColor = Colors.getColor("blackorwhite")
        
        // Instant confirmation
        self.qrScannerLabel.textColor = Colors.getColor("blackorwhite")
        self.lnConfirmationAddressView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.lnInvoiceLabel.textColor = Colors.getColor("blackorwhite")
        self.lnInvoiceCopy.tintColor = Colors.getColor("blackorwhite")
    }
}
