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
        self.appVersion.text = self.appVersion.text?.replacingOccurrences(of: "App version", with: Language.getWord(withID: "appversion"))
    }
    
    @objc func changeColors() {
        
        self.appVersion.textColor = Colors.getColor("appversion")
        self.view.backgroundColor = Colors.getColor("grey3orblue3")
    }
}
