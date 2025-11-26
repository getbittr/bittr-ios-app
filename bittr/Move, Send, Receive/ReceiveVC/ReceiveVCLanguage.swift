//
//  ReceiveVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 10/10/2024.
//

import UIKit

extension ReceiveViewController {
    
    func setBasicStyling() {
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        self.copyAddressButton.setTitle("", for: .normal)
        self.bothCopyAddressButton.setTitle("", for: .normal)
        self.refreshButton.setTitle("", for: .normal)
        self.regularButton.setTitle("", for: .normal)
        self.bothButton.setTitle("", for: .normal)
        self.instantButton.setTitle("", for: .normal)
        self.contentBackgroundButton.setTitle("", for: .normal)
        self.invoiceButton.setTitle("", for: .normal)
        self.copyInvoiceButton.setTitle("", for: .normal)
        self.scanQrButton.setTitle("", for: .normal)
        self.qrScannerBackgroundButton.setTitle("", for: .normal)
        self.lnurlButton.setTitle("", for: .normal)
        self.lnurlCopyButton.setTitle("", for: .normal)
        
        // Corner radii
        self.qrView.layer.cornerRadius = 13
        self.bothQrView.layer.cornerRadius = 13
        self.addressView.layer.cornerRadius = 8
        self.bothAddressView.layer.cornerRadius = 8
        self.bothAmountView.layer.cornerRadius = 8
        self.bothDescriptionView.layer.cornerRadius = 8
        self.createView.layer.cornerRadius = 8
        self.lnConfirmationQRView.layer.cornerRadius = 13
        self.lnConfirmationAddressView.layer.cornerRadius = 8
        self.lnurlQrView.layer.cornerRadius = 13
        self.scannerView.layer.cornerRadius = 13
        self.qrScannerCloseView.layer.cornerRadius = 13
        self.spinnerBox.layer.cornerRadius = 13
        self.viewRegular.layer.cornerRadius = 8
        self.viewBoth.layer.cornerRadius = 8
        self.viewInstant.layer.cornerRadius = 8
        self.viewLnurl.layer.cornerRadius = 8
        self.lnurlQRBackground.layer.cornerRadius = 13
        self.lnurlAddressBackground.layer.cornerRadius = 8
        
        // Selection view
        self.viewBoth.layer.shadowColor = UIColor.black.cgColor
        self.viewBoth.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.viewBoth.layer.shadowRadius = 10.0
        self.viewBoth.layer.shadowOpacity = 0.1
        self.viewRegular.layer.shadowColor = UIColor.black.cgColor
        self.viewRegular.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.viewRegular.layer.shadowRadius = 10.0
        self.viewInstant.layer.shadowColor = UIColor.black.cgColor
        self.viewInstant.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.viewInstant.layer.shadowRadius = 10.0
        self.viewLnurl.layer.shadowColor = UIColor.black.cgColor
        self.viewLnurl.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.viewLnurl.layer.shadowRadius = 10.0
        
        // Receivable sats label
        self.setShadows(forView: self.qrView)
        self.setShadows(forView: self.bothQrView)
        self.setShadows(forView: self.lnConfirmationQRView)
        self.setShadows(forView: self.lnurlQRBackground)
    }
    
    func setWords() {
        
        self.topLabel.text = Language.getWord(withID: "receivebitcoin")
        self.labelRegular.text = Language.getWord(withID: "regular")
        self.labelBoth.text = Language.getWord(withID: "both")
        self.labelInstant.text = Language.getWord(withID: "instant")
        self.labelUrl.text = Language.getWord(withID: "url")
        self.subtitleRegular.text = Language.getWord(withID: "thisisanaddress")
        self.subtitleBoth.text = Language.getWord(withID: "subtitleboth")
        self.bothAmountTextField.placeholder = Language.getWord(withID: "insatoshis")
        self.createInvoiceLabel.text = Language.getWord(withID: "createinvoice")
        self.qrScannerLabel.text = Language.getWord(withID: "lnurlscannerlabel")
        self.qrScannerCloseLabel.text = Language.getWord(withID: "close")
        self.bothAmountLabel.text = Language.getWord(withID: "bothamountlabel")
        self.spinnerLabel.text = Language.getWord(withID: "handlinglnurl")
        
    }
    
    func changeColors() {
        
        // View
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        
        // Switch
        self.viewRegular.backgroundColor = Colors.getColor("white0.7orblue2")
        self.viewBoth.backgroundColor = Colors.getColor("whiteorblue3")
        self.viewInstant.backgroundColor = Colors.getColor("white0.7orblue2")
        self.viewLnurl.backgroundColor = Colors.getColor("white0.7orblue2")
        self.labelRegular.textColor = Colors.getColor("blackorwhite")
        self.labelInstant.textColor = Colors.getColor("blackorwhite")
        self.labelBoth.textColor = Colors.getColor("blackorwhite")
        self.labelUrl.textColor = Colors.getColor("blackorwhite")
        self.iconLightning.tintColor = Colors.getColor("blackorwhite")
        self.iconLnurl.tintColor = Colors.getColor("blackorwhite")
        
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
        self.refreshIcon.tintColor = Colors.getColor("blackorwhite")
        
        // LNURL
        self.lnurlAddressBackground.backgroundColor = Colors.getColor("white0.7orblue2")
        self.lnurlAddressLabel.textColor = Colors.getColor("blackorwhite")
        self.lnurlCopyIcon.tintColor = Colors.getColor("blackorwhite")
        
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
