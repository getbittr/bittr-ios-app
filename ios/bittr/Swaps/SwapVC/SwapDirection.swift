//
//  SwapDirection.swift
//  bittr
//
//  Created by Tom Melters on 4/20/26.
//

import UIKit

extension SwapViewController {
    
    func switchDirection() {
        self.showAlert(title: Language.getWord(withID: "swapfunds"), message: Language.getWord(withID: "swapdirection"), buttons: [.dismiss(Language.getWord(withID: "cancel")), .action(Language.getWord(withID: "onchaintolightning")) { self.switchDirection(.onchainToLightning) }, .action(Language.getWord(withID: "lightningtoonchain")) { self.switchDirection(.lightningToOnchain) }])
    }
    
    func switchDirection(_ swapDirection:SwapDirection) {
        self.swapDirection = swapDirection
        self.fromLabel.text = swapDirection == .onchainToLightning ? Language.getWord(withID: "onchaintolightning") : Language.getWord(withID: "lightningtoonchain")
        self.calculateSendableAmount()
    }
}
