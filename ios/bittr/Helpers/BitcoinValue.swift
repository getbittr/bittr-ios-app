//
//  BitcoinValue.swift
//  bittr
//
//  Created by Tom Melters on 8/6/25.
//

import UIKit

class BitcoinValue: NSObject {
    
    var currentValue:CGFloat = 0
    var chosenCurrency:String = "€"
    var apiUrl:String = "\(EnvironmentConfig.bittrAPIBaseURL)/price/btc/historical/eur"
}

