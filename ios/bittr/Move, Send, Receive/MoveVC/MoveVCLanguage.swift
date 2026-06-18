//
//  MoveVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension MoveViewController {
    
    func setWords() {
        
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
        self.swapView.backgroundColor = Colors.getColor("yelloworblue2")
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
        
        if CacheManager.darkModeIsOn() {
            self.swapIcon.image = UIImage(named: "iconswap")
        } else {
            self.swapIcon.image = UIImage(named: "iconswapwhite")
        }
    }
    
    func setBasicStyling() {
        
        // Button titles.
        self.receiveButton.setTitle("", for: .normal)
        self.sendButton.setTitle("", for: .normal)
        self.channelButton.setTitle("", for: .normal)
        self.swapButton.setTitle("", for: .normal)
        
        // Corner radii
        self.leftCard.layer.cornerRadius = 8
        self.rightCard.layer.cornerRadius = 8
        self.viewTotal.layer.cornerRadius = 13
        self.viewRegular.layer.cornerRadius = 13
        self.viewInstant.layer.cornerRadius = 13
        self.yellowCard.layer.cornerRadius = 20
        self.swapView.layer.cornerRadius = self.swapView.bounds.height/2
        self.rightCard.setShadow()
        self.leftCard.setShadow()
        
        // Shadows
        self.yellowCard.setShadow()
        self.swapView.setShadow()
    }
}
