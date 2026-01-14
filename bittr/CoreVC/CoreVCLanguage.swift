//
//  CoreVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 9/9/25.
//

import UIKit

extension CoreViewController {
    
    @objc func changeColors() {
        
        // Main view.
        self.view.backgroundColor = Colors.getColor("grey3orblue1")
        
        // Menu items.
        self.walletView.backgroundColor = Colors.getColor("grey3orblue1")
        self.academyView.backgroundColor = Colors.getColor("grey3orblue1")
        self.settingsView.backgroundColor = Colors.getColor("grey3orblue1")
        
        self.fullViewCover.backgroundColor = Colors.getColor("yelloworblue3")
        
        // Top bar.
        self.lowerTopBar.backgroundColor = Colors.getColor("yelloworblue3")
        self.topBar.backgroundColor = Colors.getColor("transparentyellow")
        self.upperYellowCurve.fillColor = Colors.getColor("transparentyellow")
        self.lowerYellowCurve.fillColor = Colors.getColor("yelloworblue3")
        
        if CacheManager.darkModeIsOn() {
            // Dark mode is on.
            self.leftImageUnselected.image = UIImage(named: "menuwalletwhite")
            self.middleImageUnselected.image = UIImage(named: "menuacademywhite")
            self.rightImageUnselected.image = UIImage(named: "menusettingswhite")
            self.walletLabel.textColor = UIColor.white
            self.academyLabel.textColor = UIColor.white
            
            self.finalLogoDarkMode.alpha = 1
            self.bittrTextDarkMode.alpha = 1
        } else {
            // Dark mode is off.
            self.leftImageUnselected.image = UIImage(named: "menuwalletblack")
            self.middleImageUnselected.image = UIImage(named: "menuacademyblack")
            self.rightImageUnselected.image = UIImage(named: "menusettingsblack")
            self.walletLabel.textColor = UIColor(displayP3Red: 83/255, green: 83/255, blue: 83/255, alpha: 1)
            self.academyLabel.textColor = UIColor(displayP3Red: 83/255, green: 83/255, blue: 83/255, alpha: 1)
            
            self.finalLogoDarkMode.alpha = 0
            self.bittrTextDarkMode.alpha = 0
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
