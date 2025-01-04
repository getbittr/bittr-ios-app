//
//  BittrValue.swift
//  bittr
//
//  Created by Tom Melters on 04/01/2025.
//

import UIKit

extension HomeViewController {
    
    @objc func openValueVC() {
        self.performSegue(withIdentifier: "HomeToValue", sender: self)
    }
}
