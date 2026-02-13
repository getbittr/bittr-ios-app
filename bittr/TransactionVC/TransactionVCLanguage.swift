//
//  TransactionVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension TransactionViewController {
    
    func setWords() {
        
        self.titleAmount.text = Language.getWord(withID: "amount")
        self.titleType.text = Language.getWord(withID: "type")
        self.titleSwapId.text = Language.getWord(withID: "swapid")
        self.titleSwapStatus.text = Language.getWord(withID: "swapstatus")
        self.titleFees.text = Language.getWord(withID: "feespaid")
        self.titleConfirmations.text = Language.getWord(withID: "confirmations")
        self.titleDescription.text = Language.getWord(withID: "description")
        self.titleCurrentValue.text = Language.getWord(withID: "currentvalue")
        self.titleProfit.text = Language.getWord(withID: "profit")
        self.titleGrossAmount.text = Language.getWord(withID: "receivedatbittr")
        self.titleTransferFee.text = Language.getWord(withID: "transferfee")
        self.titleBittrFee.text = Language.getWord(withID: "bittrfee")
        self.titleSurcharge.text = Language.getWord(withID: "surcharge")
        self.titleNetAmount.text = Language.getWord(withID: "purchasevalue")
        self.titleBittrCurrentValue.text = Language.getWord(withID: "currentvalue")
        self.titleNote.text = Language.getWord(withID: "note")
        self.titleAddANote.text = Language.getWord(withID: "addanote")
        self.bittrPayoutSubtitle.text = Language.getWord(withID: "goodjob")
        self.alertTitle.text = Language.getWord(withID: "reminder")
        self.alertLabel.text = Language.getWord(withID: "reminderbody")
        
    }
    
    func changeColors() {
        
        // Card
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
        
        // Alert
        self.alertCard.backgroundColor = Colors.getColor("whiteorblue2")
        self.alertLabel.textColor = Colors.getColor("blackorwhite")
        
        // Date
        self.labelDate.textColor = Colors.getColor("blackorwhite")
        
        // Amount
        self.cardAmount.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelAmount.textColor = Colors.getColor("blackorwhite")
        
        // Type
        self.cardType.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelType.textColor = Colors.getColor("blackorwhite")
        self.typeBoltImage.tintColor = Colors.getColor("blackorwhite")
        
        // Swap ID and status
        self.cardSwapId.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelSwapId.textColor = Colors.getColor("blackorwhite")
        self.labelSwapStatus.textColor = Colors.getColor("blackorwhite")
        self.swapArrowImage.tintColor = Colors.getColor("blackorwhite")
        
        // Fees
        self.cardFees.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelFees.textColor = Colors.getColor("blackorwhite")
        
        // Confirmations
        self.cardConfirmations.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelConfirmations.textColor = Colors.getColor("blackorwhite")
        
        // Description
        self.cardDescription.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelDescription.textColor = Colors.getColor("blackorwhite")
        
        // IDs
        self.cardTopId.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelTopId.textColor = Colors.getColor("blackorwhite")
        self.labelBottomId.textColor = Colors.getColor("blackorwhite")
        self.urlImageTopId.tintColor = Colors.getColor("blackorwhite")
        self.urlImageBottomId.tintColor = Colors.getColor("blackorwhite")
        
        // Value
        self.cardValue.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelCurrentValue.textColor = Colors.getColor("blackorwhite")
        
        // Bittr fees
        self.cardBittrFees.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelGrossAmount.textColor = Colors.getColor("blackorwhite")
        self.labelTransferFee.textColor = Colors.getColor("blackorwhite")
        self.labelBittrFee.textColor = Colors.getColor("blackorwhite")
        self.labelSurcharge.textColor = Colors.getColor("blackorwhite")
        self.labelNetAmount.textColor = Colors.getColor("blackorwhite")
        self.labelBittrCurrentValue.textColor = Colors.getColor("blackorwhite")
        self.sumLine.backgroundColor = Colors.getColor("blackorwhite")
        
        // Note
        self.cardNote.backgroundColor = Colors.getColor("whiteorblue3")
        self.labelNote.textColor = Colors.getColor("blackorwhite")
        
        // Add a note
        self.titleAddANote.textColor = Colors.getColor("blackorwhite")
        self.imageAddANote.tintColor = Colors.getColor("blackorwhite")
        
        // Bittr
        self.bittrPayoutSubtitle.textColor = Colors.getColor("blackorwhite")
    }
}
