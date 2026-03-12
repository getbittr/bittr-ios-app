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
        self.copyAddressButton.setTitle("", for: .normal)
        self.bothCopyAddressButton.setTitle("", for: .normal)
        self.refreshButton.setTitle("", for: .normal)
        self.regularButton.setTitle("", for: .normal)
        self.bothButton.setTitle("", for: .normal)
        self.instantButton.setTitle("", for: .normal)
        self.contentBackgroundButton.setTitle("", for: .normal)
        self.copyInvoiceButton.setTitle("", for: .normal)
        self.lnurlButton.setTitle("", for: .normal)
        self.lnurlCopyButton.setTitle("", for: .normal)
        self.btcButton.setTitle("", for: .normal)
        
        // Corner radii
        self.yellowCard.layer.cornerRadius = 13
        self.qrView.layer.cornerRadius = 13
        self.bothQrView.layer.cornerRadius = 13
        self.addressView.layer.cornerRadius = 8
        self.bothAddressView.layer.cornerRadius = 8
        self.bothAmountView.layer.cornerRadius = 8
        self.bothDescriptionView.layer.cornerRadius = 8
        self.lnConfirmationQRView.layer.cornerRadius = 13
        self.lnConfirmationAddressView.layer.cornerRadius = 8
        self.spinnerBox.layer.cornerRadius = 13
        self.viewRegular.layer.cornerRadius = 8
        self.viewBoth.layer.cornerRadius = 8
        self.viewInstant.layer.cornerRadius = 8
        self.viewLnurl.layer.cornerRadius = 8
        self.lnurlQRBackground.layer.cornerRadius = 13
        self.lnurlAddressBackground.layer.cornerRadius = 8
        self.btcView.layer.cornerRadius = 8
        
        // Selection view
        self.viewBoth.setShadow()
        self.viewBoth.layer.shadowOpacity = 0.1
        self.viewRegular.setShadow()
        self.viewRegular.layer.shadowOpacity = 0
        self.viewInstant.setShadow()
        self.viewInstant.layer.shadowOpacity = 0
        self.viewLnurl.setShadow()
        self.viewLnurl.layer.shadowOpacity = 0
        
        // Receivable sats label
        self.qrView.setShadow()
        self.bothQrView.setShadow()
        self.lnConfirmationQRView.setShadow()
        self.lnurlQRBackground.setShadow()
        self.btcView.setShadow()
        self.yellowCard.setShadow()
    }
    
    func setWords() {
        
        self.labelRegular.text = Language.getWord(withID: "regular")
        self.labelBoth.text = Language.getWord(withID: "both")
        self.labelInstant.text = Language.getWord(withID: "instant")
        self.labelUrl.text = Language.getWord(withID: "url")
        self.bothAmountTextField.placeholder = Language.getWord(withID: "insatoshis")
        self.bothAmountLabel.text = Language.getWord(withID: "bothamountlabel")
        self.spinnerLabel.text = Language.getWord(withID: "handlinglnurl")
        
    }
    
    func changeColors() {
        
        // View
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
        
        // Switch
        self.viewRegular.backgroundColor = Colors.getColor("white0.7orblue1")
        self.viewBoth.backgroundColor = Colors.getColor("whiteorblue3")
        self.viewInstant.backgroundColor = Colors.getColor("white0.7orblue1")
        self.viewLnurl.backgroundColor = Colors.getColor("white0.7orblue1")
        self.labelRegular.textColor = Colors.getColor("blackorwhite")
        self.labelInstant.textColor = Colors.getColor("blackorwhite")
        self.labelBoth.textColor = Colors.getColor("blackorwhite")
        self.labelUrl.textColor = Colors.getColor("blackorwhite")
        self.iconLightning.tintColor = Colors.getColor("blackorwhite")
        self.iconLnurl.tintColor = Colors.getColor("blackorwhite")
        
        // Regular
        self.addressView.backgroundColor = Colors.getColor("white0.7orblue1")
        self.bothAddressView.backgroundColor = Colors.getColor("white0.7orblue1")
        self.addressLabel.textColor = Colors.getColor("blackorwhite")
        self.bothAddressLabel.textColor = Colors.getColor("blackorwhite")
        self.addressSpinner.color = Colors.getColor("blackorwhite")
        self.addressCopy.tintColor = Colors.getColor("blackorwhite")
        self.bothAddressCopy.tintColor = Colors.getColor("blackorwhite")
        self.refreshIcon.tintColor = Colors.getColor("blackorwhite")
        self.btcView.backgroundColor = Colors.getColor("whiteorblue3")
        self.btcLabel.textColor = Colors.getColor("blackorwhite")
        
        // LNURL
        self.lnurlAddressBackground.backgroundColor = Colors.getColor("white0.7orblue1")
        self.lnurlAddressLabel.textColor = Colors.getColor("blackorwhite")
        self.lnurlCopyIcon.tintColor = Colors.getColor("blackorwhite")
        
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
        
        // Instant confirmation
        self.lnConfirmationAddressView.backgroundColor = Colors.getColor("white0.7orblue1")
        self.lnInvoiceLabel.textColor = Colors.getColor("blackorwhite")
        self.lnInvoiceCopy.tintColor = Colors.getColor("blackorwhite")
    }
}
