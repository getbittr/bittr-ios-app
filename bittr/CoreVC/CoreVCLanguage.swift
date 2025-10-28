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
        
        if CacheManager.darkModeIsOn() {
            // Dark mode is on.
            self.leftImageUnselected.image = UIImage(named: "menuwalletwhite")
            self.middleImageUnselected.image = UIImage(named: "menuacademywhite")
            self.rightImageUnselected.image = UIImage(named: "menusettingswhite")
            self.walletLabel.textColor = UIColor.white
            self.academyLabel.textColor = UIColor.white
            
            self.yellowcurve.image = UIImage(named: "yellowcurvedark")
            self.lowerYellowcurve.image = UIImage(named: "yellowcurvedark")
            self.bittrText.image = UIImage(named: "bittrtextwhite")
            self.finalLogo.image = UIImage(named: "logodarkmode80")
        } else {
            // Dark mode is off.
            self.leftImageUnselected.image = UIImage(named: "menuwalletblack")
            self.middleImageUnselected.image = UIImage(named: "menuacademyblack")
            self.rightImageUnselected.image = UIImage(named: "menusettingsblack")
            self.walletLabel.textColor = UIColor(displayP3Red: 83/255, green: 83/255, blue: 83/255, alpha: 1)
            self.academyLabel.textColor = UIColor(displayP3Red: 83/255, green: 83/255, blue: 83/255, alpha: 1)
            
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
