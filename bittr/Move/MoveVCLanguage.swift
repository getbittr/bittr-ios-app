//
//  MoveVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension MoveViewController {
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "balance")
        self.subtitleLabel.text = Language.getWord(withID: "walletsubtitle")
        self.labelRegular.text = Language.getWord(withID: "regular")
        self.labelInstant.text = Language.getWord(withID: "instant")
        self.sendLabel.text = Language.getWord(withID: "send")
        self.receiveLabel.text = Language.getWord(withID: "receive")
    }
    
    func changeColors() {
        
        self.subtitleLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.view.backgroundColor = Colors.getColor(color: "yelloworblue1")
        
        self.yellowCard.backgroundColor = Colors.getColor(color: "yelloworblue2")
        self.viewTotal.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.viewInstant.backgroundColor = Colors.getColor(color: "whiteorblue3")
        self.viewRegular.backgroundColor = Colors.getColor(color: "whiteorblue3")
        
        self.leftCard.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.rightCard.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        
        self.conversionTotal.textColor = Colors.getColor(color: "blackorwhite")
        self.conversionInstant.textColor = Colors.getColor(color: "blackorwhite")
        self.conversionRegular.textColor = Colors.getColor(color: "blackorwhite")
        self.satsTotal.textColor = Colors.getColor(color: "blackorwhite")
        self.satsRegular.textColor = Colors.getColor(color: "blackorwhite")
        self.satsInstant.textColor = Colors.getColor(color: "blackorwhite")
        self.questionMark.tintColor = Colors.getColor(color: "blackorwhite")
        self.sendLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.receiveLabel.textColor = Colors.getColor(color: "blackorwhite")
    }
}
