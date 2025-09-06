//
//  SwapVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 9/4/25.
//

import UIKit

extension SwapViewController {
    
    func setLanguage() {
        self.topLabel.text = Language.getWord(withID: "swapfunds")
        self.subtitleLabel.text = Language.getWord(withID: "swapsubtitle")
        self.moveLabel.text = Language.getWord(withID: "move")
        self.nextLabel.text = Language.getWord(withID: "next")
        self.fromLabel.text = Language.getWord(withID: "onchaintolightning")
        self.titleDirection.text = Language.getWord(withID: "direction")
        self.titleAmount.text = Language.getWord(withID: "amount")
        self.titleFees.text = Language.getWord(withID: "fees")
        self.titleStatus.text = Language.getWord(withID: "status")
        self.downloadLabel.text = Language.getWord(withID: "downloadswapfile")
    }
    
    @objc func changeColors() {
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.topLabel.textColor = Colors.getColor("whiteoryellow")
        self.subtitleLabel.textColor = Colors.getColor("blackorwhite")
        self.moveLabel.textColor = Colors.getColor("blackoryellow")
        self.centerCard.backgroundColor = Colors.getColor("yelloworblue1")
        self.confirmCard.backgroundColor = Colors.getColor("yelloworblue1")
        self.pendingCoverView.backgroundColor = Colors.getColor("yelloworblue1")
        self.confirmTopLabel.textColor = Colors.getColor("whiteoryellow")
        self.confirmDirection.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmAmount.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmFees.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmStatus.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmDirectionLabel.textColor = Colors.getColor("blackorwhite")
        self.confirmAmountLabel.textColor = Colors.getColor("blackorwhite")
        self.confirmFeesLabel.textColor = Colors.getColor("blackorwhite")
        self.confirmStatusLabel.textColor = Colors.getColor("blackorwhite")
        self.availableAmountLabel.textColor = Colors.getColor("blackorwhite")
        self.questionMark.tintColor = Colors.getColor("blackorwhite")
        self.statusQuestionIcon.tintColor = Colors.getColor("blackorwhite")
        self.amountTextField.backgroundColor = Colors.getColor("white0.7orblue2")
        self.fromView.backgroundColor = Colors.getColor("whiteorblue3")
        self.fromLabel.textColor = Colors.getColor("blackorwhite")
        self.downloadLabel.textColor = Colors.getColor("blackorwhite")
        
        self.amountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteramountofsatoshis"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        self.amountTextField.textColor = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.swapIcon.image = UIImage(named: "iconswap")
            self.confirmTopIcon.image = UIImage(named: "iconswap")
            self.resetIcon.image = UIImage(named: "iconresetwhite")
            self.downloadIcon.image = UIImage(named: "icondownload")
        } else {
            self.swapIcon.image = UIImage(named: "iconswapwhite")
            self.confirmTopIcon.image = UIImage(named: "iconswapwhite")
            self.resetIcon.image = UIImage(named: "iconreset")
            self.downloadIcon.image = UIImage(named: "icondownloadblack")
        }
    }
    
}
