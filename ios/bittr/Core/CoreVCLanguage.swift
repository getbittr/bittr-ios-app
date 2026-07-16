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
        self.statusView.layer.cornerRadius = 13
        self.settingsView.layer.cornerRadius = 8
        self.academyView.layer.cornerRadius = 8
        self.walletView.layer.cornerRadius = 8
        self.yearView.layer.cornerRadius = 12.5
        self.settingsContainer.layer.cornerRadius = 20
        
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
        self.settingsBackgroundButton.setTitle("", for: .normal)
        
        // Add observers.
        NotificationCenter.default.addObserver(self, selector: #selector(newNotification), name: NSNotification.Name(rawValue: "newNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBitcoinURI), name: NSNotification.Name(rawValue: "handleBitcoinURI"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLightningURI), name: NSNotification.Name(rawValue: "handleLightningURI"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        // Test IDs
        self.leftButton.accessibilityIdentifier = TestID.Nav.walletButton
        self.middleButton.accessibilityIdentifier = TestID.Nav.academyButton
        self.rightButton.accessibilityIdentifier = TestID.Nav.settingsButton
        self.statusView.accessibilityIdentifier = TestID.Sync.statusView
        self.syncCloseButton.accessibilityIdentifier = TestID.Sync.closeButton
        
        // Settings handler.
        let settingsPan = UIPanGestureRecognizer(target: self, action: #selector(self.handleSettingsPan(_:)))
        settingsPan.delegate = self
        self.settingsContainer.addGestureRecognizer(settingsPan)
    }
}
