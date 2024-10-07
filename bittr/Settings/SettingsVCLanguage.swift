//
//  SettingsVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension SettingsViewController {
    
    func setWords() {
        
        self.appVersion.text = self.appVersion.text?.replacingOccurrences(of: "App version", with: Language.getWord(withID: "appversion"))
    }
}
