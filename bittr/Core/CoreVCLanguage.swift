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
        self.infoContainerView.backgroundColor = Colors.getColor("yelloworblue3")
        
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
        
        // Year view
        self.yearView.backgroundColor = Colors.getColor("whiteorblue3")
        self.yearLabel.textColor = Colors.getColor("blackorwhite")
        
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
        self.statusFinal.text = Language.getWord(withID: "finalcalculations")
    }
    
    func setBasicStyling() {
        
        // Corner radii
        self.selectedView.layer.cornerRadius = 8
        self.pendingView.layer.cornerRadius = 13
        self.statusView.layer.cornerRadius = 13
        self.settingsView.layer.cornerRadius = 8
        self.academyView.layer.cornerRadius = 8
        self.walletView.layer.cornerRadius = 8
        self.yearView.layer.cornerRadius = 12.5
        
        // Shadows
        self.walletView.setShadow()
        self.academyView.setShadow()
        self.settingsView.setShadow()
        self.yearView.setShadow()
        
        // Button titles
        self.leftButton.setTitle("", for: .normal)
        self.middleButton.setTitle("", for: .normal)
        self.rightButton.setTitle("", for: .normal)
        self.syncCloseButton.setTitle("", for: .normal)
        
        // Set curve color to yellow for app launch.
        self.upperYellowCurve.fillColor = UIColor(displayP3Red: 246/255, green: 199/255, blue: 68/255, alpha: 0.85)
        self.lowerYellowCurve.fillColor = UIColor(displayP3Red: 246/255, green: 199/255, blue: 68/255, alpha: 1)
        
    }
}
