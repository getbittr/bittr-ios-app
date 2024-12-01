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
        
        self.subtitleLabel.textColor = Colors.getColor("blackorwhite")
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        
        self.yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
        self.viewTotal.backgroundColor = Colors.getColor("whiteorblue3")
        self.viewInstant.backgroundColor = Colors.getColor("whiteorblue3")
        self.viewRegular.backgroundColor = Colors.getColor("whiteorblue3")
        
        self.leftCard.backgroundColor = Colors.getColor("white0.7orblue2")
        self.rightCard.backgroundColor = Colors.getColor("white0.7orblue2")
        
        self.conversionTotal.textColor = Colors.getColor("blackorwhite")
        self.conversionInstant.textColor = Colors.getColor("blackorwhite")
        self.conversionRegular.textColor = Colors.getColor("blackorwhite")
        self.satsTotal.textColor = Colors.getColor("blackorwhite")
        self.satsRegular.textColor = Colors.getColor("blackorwhite")
        self.satsInstant.textColor = Colors.getColor("blackorwhite")
        self.questionMark.tintColor = Colors.getColor("blackorwhite")
        self.sendLabel.textColor = Colors.getColor("blackorwhite")
        self.receiveLabel.textColor = Colors.getColor("blackorwhite")
    }
}
