//
//  Int.swift
//  bittr
//
//  Created by Tom Melters on 2/24/26.
//

import UIKit

extension Int {
    
    func inBTC() -> CGFloat {
        return (CGFloat(self) / 100_000_000)
    }
    
}
