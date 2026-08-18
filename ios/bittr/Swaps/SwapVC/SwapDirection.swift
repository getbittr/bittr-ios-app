//
//  SwapDirection.swift
//  bittr
//
//  Created by Tom Melters on 4/20/26.
//

import UIKit

extension SwapViewController {
    
    func switchDirection() {
        self.showAlert(presentingController: self, title: Language.getWord(withID: "swapfunds"), message: Language.getWord(withID: "swapdirection"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "onchaintolightning"), Language.getWord(withID: "lightningtoonchain")], actions: [nil, { self.switchOnchainToLightning() }, { self.switchLightningToOnchain() }])
    }
    
    @objc func switchOnchainToLightning() {
        self.hideAlert()
        self.fromLabel.text = Language.getWord(withID: "onchaintolightning")
        self.swapDirection = .onchainToLightning
        self.calculateSendableAmount()
    }
    
    @objc func switchLightningToOnchain() {
        self.hideAlert()
        self.fromLabel.text = Language.getWord(withID: "lightningtoonchain")
        self.swapDirection = .lightningToOnchain
        self.calculateSendableAmount()
    }
}
