//
//  CGFloat.swift
//  bittr
//
//  Created by Tom Melters on 2/24/26.
//

import UIKit

extension CGFloat {
    
    func formattedBitcoin() -> String {
        // Debug: print the values to see what's happening
        print("Debug - btcValue: \(self)")
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        
        // Handle very small amounts (less than 1 satoshi)
        if self < 0.00000001 {
            return "0.00000000"
        }
        
        let result = formatter.string(from: NSNumber(value: self)) ?? "0.00000000"
        print("Debug - formatted result: \(result)")
        return result
    }
    
    func twoDecimals() -> CGFloat {
        return (self*100).rounded()/100
    }
    
    func toString() -> String {
        
        if self == 0 {
            return "0\(Locale.current.decimalSeparator!)00"
        } else {
            let string = "\(self)".fixDecimals()
            if string.split(separator: Locale.current.decimalSeparator!)[1].count == 1 {
                return "\(string)0"
            } else {
                return string
            }
        }
    }
    
    func inSatoshis() -> Int {
        // Safety check for invalid values
        guard self.isFinite && !self.isNaN else {
            print("⚠️ Warning: Invalid CGFloat value (\(self)) in inSatoshis()")
            return 0
        }
        
        // Use direct multiplication to avoid precision issues with Decimal
        let satoshis = self * 100_000_000
        return Int(satoshis.rounded())
    }
    
    func inBTC() -> CGFloat {
        return (self / 100_000_000)
    }
    
    func between(a: CGFloat, b: CGFloat) -> Bool {
        return self >= Swift.min(a, b) && self <= Swift.max(a, b)
    }
}
