//
//  SwapDirection.swift
//  bittr
//
//  Created by Tom Melters on 4/20/26.
//

import UIKit

extension SwapViewController {
    
    func switchDirection() {
        self.showAlert(presentingController: self, title: Language.getWord(withID: "swapfunds"), message: Language.getWord(withID: "swapdirection"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "onchaintolightning"), Language.getWord(withID: "lightningtoonchain")], actions: [nil, { self.switchDirection(.onchainToLightning) }, { self.switchDirection(.lightningToOnchain) }])
    }
    
    func switchDirection(_ swapDirection:SwapDirection) {
        self.swapDirection = swapDirection
        self.fromLabel.text = swapDirection == .onchainToLightning ? Language.getWord(withID: "onchaintolightning") : Language.getWord(withID: "lightningtoonchain")
        self.calculateSendableAmount()
    }
}
