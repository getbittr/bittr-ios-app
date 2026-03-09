//
//  ConfirmLanguage.swift
//  bittr
//
//  Created by Tom Melters on 3/9/26.
//

import Foundation
import UIKit

extension ConfirmSendViewController {
    
    func setBasicStyling() {
        
        // Buttons
        self.buttonFast.setTitle("", for: .normal)
        self.buttonMedium.setTitle("", for: .normal)
        self.buttonSlow.setTitle("", for: .normal)
        self.backButton.setTitle("", for: .normal)
        self.confirmButton.setTitle("", for: .normal)
        
        // Corner radii
        self.yellowCard.layer.cornerRadius = 13
        self.addressView.layer.cornerRadius = 8
        self.amountView.layer.cornerRadius = 8
        self.lightningFeesView.layer.cornerRadius = 8
        self.feesViewFast.layer.cornerRadius = 8
        self.feesViewMedium.layer.cornerRadius = 8
        self.feesViewSlow.layer.cornerRadius = 8
        self.backView.layer.cornerRadius = 8
        self.confirmView.layer.cornerRadius = 8
        
        // Shadows
        self.yellowCard.setShadow()
        self.feesViewFast.setShadow()
        self.feesViewMedium.setShadow()
        self.feesViewSlow.setShadow()
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
        
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        self.addressLabel.textColor = Colors.getColor("blackorwhite")
        self.amountLabel.textColor = Colors.getColor("blackorwhite")
        self.amountFiatLabel.textColor = Colors.getColor("blackorwhite")
        self.lightningFeesLabel.textColor = Colors.getColor("blackorwhite")
        self.feesTopLabel.textColor = Colors.getColor("blackorwhite")
        
        self.addressView.backgroundColor = Colors.getColor("whiteorblue3")
        self.amountView.backgroundColor = Colors.getColor("whiteorblue3")
        self.lightningFeesView.backgroundColor = Colors.getColor("whiteorblue3")
        
        self.feesViewFast.backgroundColor = Colors.getColor("white0.7orblue1")
        self.feesViewMedium.backgroundColor = Colors.getColor("whiteorblue3")
        self.feesViewSlow.backgroundColor = Colors.getColor("white0.7orblue1")
        
        self.timeFast.textColor = Colors.getColor("blackoryellow")
        self.timeMedium.textColor = Colors.getColor("blackoryellow")
        self.timeSlow.textColor = Colors.getColor("blackoryellow")
        
        self.feesFast.textColor = Colors.getColor("blackorwhite")
        self.feesMedium.textColor = Colors.getColor("blackorwhite")
        self.feesSlow.textColor = Colors.getColor("blackorwhite")
        
        self.feesFiatFast.textColor = Colors.getColor("blackorwhite")
        self.feesFiatMedium.textColor = Colors.getColor("blackorwhite")
        self.feesFiatSlow.textColor = Colors.getColor("blackorwhite")
        
    }
    
    func setLanguage() {
        
        self.topLabel.text = Language.getWord(withID: "checkdetails")
        self.addressTitle.text = Language.getWord(withID: "address")
        self.amountTitle.text = Language.getWord(withID: "amount")
        self.lightningFeesTitle.text = Language.getWord(withID: "estimatedfees")
        self.feesTopLabel.text = Language.getWord(withID: "feerate")
        self.confirmLabel.text = Language.getWord(withID: "send")
        
        self.timeFast.text = Language.getWord(withID: "10mins")
        self.timeMedium.text = Language.getWord(withID: "1hour")
        self.timeSlow.text = Language.getWord(withID: "1day")
        
    }
}
