//
//  SettingsVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension SettingsViewController {
    
    @objc func setWords() {
        
        self.settingsTableView.reloadData()
        // Version + build number (and git hash, when the build phase set it) are
        // read from the bundle at runtime — no hard-coded number in the storyboard.
        self.appVersion.text = "\(Language.getWord(withID: "appversion")) \(AppVersion.displayString)"
    }
    
    @objc func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.addHeader(iconLight: "menusettingswhite", iconDark: "menusettingsyellow", title: Language.getWord(withID: "settings"))
    }
}
