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
}
