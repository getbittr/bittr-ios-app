//
//  CoreVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 9/9/25.
//

import UIKit

extension CoreViewController {
    
    @objc func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("grey3orblue1")
        self.leftWhite.backgroundColor = Colors.getColor("grey3orblue1")
        self.middleWhite.backgroundColor = Colors.getColor("grey3orblue1")
        self.rightWhite.backgroundColor = Colors.getColor("grey3orblue1")
        self.fullViewCover.backgroundColor = Colors.getColor("yelloworblue3")
        
        self.lowerTopBar.backgroundColor = Colors.getColor("yelloworblue3")
        self.topBar.backgroundColor = Colors.getColor("transparentyellow")
        
        if CacheManager.darkModeIsOn() {
            // Dark mode is on.
            self.leftImageUnselected.image = UIImage(named: "buttonpigwhite")
            self.middleImageUnselected.image = UIImage(named: "buttonmagazinewhite")
            self.rightImageUnselected.image = UIImage(named: "buttonsettingswhite")
            self.yellowcurve.image = UIImage(named: "yellowcurvedark")
            self.lowerYellowcurve.image = UIImage(named: "yellowcurvedark")
            self.bittrText.image = UIImage(named: "bittrtextwhite")
            self.finalLogo.image = UIImage(named: "logodarkmode80")
        } else {
            // Dark mode is off.
            self.leftImageUnselected.image = UIImage(named: "buttonpigblack")
            self.middleImageUnselected.image = UIImage(named: "buttonmagazineblack")
            self.rightImageUnselected.image = UIImage(named: "buttonsettingsblack")
            self.lowerYellowcurve.image = UIImage(named: "yellowcurve")
            self.yellowcurve.image = UIImage(named: "yellowcurve")
            self.bittrText.image = UIImage(named: "bittrtext")
            self.finalLogo.image = UIImage(named: "logo80")
        }
    }
    
    @objc func setWords() {
        
        self.statusConversion.text = Language.getWord(withID: "fetchconversionrates")
        self.statusLightning.text = Language.getWord(withID: "startlightningnode")
        self.statusBlockchain.text = Language.getWord(withID: "initiatewallet")
        self.statusSyncing.text = Language.getWord(withID: "syncwallet")
        self.statusFinal.text = Language.getWord(withID: "finalcalculations")
    }
}
