//
//  Untitled.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension HomeViewController {
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "syncing")
        self.sendLabel.text = Language.getWord(withID: "send")
        self.receiveLabel.text = Language.getWord(withID: "receive")
        self.buyLabel.text = Language.getWord(withID: "buy")
        self.profitLabel.text = "🌱  " + Language.getWord(withID: "totalprofit")
    }
}
