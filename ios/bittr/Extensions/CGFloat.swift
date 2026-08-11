//
//  CGFloat.swift
//  bittr
//
//  Created by Tom Melters on 2/24/26.
//

import UIKit

extension CGFloat {
    
    func formattedBitcoin() -> String {
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        
        // Handle very small amounts (less than 1 satoshi)
        if self < 0.00000001 {
            return "0.00000000"
        }
        
        return formatter.string(from: NSNumber(value: self)) ?? "0.00000000"
    }
    
    func twoDecimals() -> CGFloat {
        return (self*100).rounded()/100
    }
    
    // Two decimal places, using the device's decimal separator.
    func toString() -> String {
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        guard self.isFinite, let formatted = formatter.string(from: NSNumber(value: Double(self))) else {
            return "0\(Locale.current.decimalSeparator ?? ".")00"
        }
        return formatted
    }
    
    // This bitcoin amount in whole satoshis.
    func inSatoshis() -> Int {
        // Safety check for invalid values
        guard self.isFinite, self > 0 else { return 0 }
        
        let satoshis = (self * CGFloat(Bitcoin.satoshisPerBitcoin)).rounded()
        guard satoshis < CGFloat(Bitcoin.maximumSatoshis) else { return Bitcoin.maximumSatoshis }
        return Int(satoshis)
    }
    
    func inBTC() -> CGFloat {
        return (self / 100_000_000)
    }
    
    func between(a: CGFloat, b: CGFloat) -> Bool {
        return self >= Swift.min(a, b) && self <= Swift.max(a, b)
    }
}

// MARK: - Fee rates

extension Double {
    
    // The whole sat/vB rate a transaction is actually broadcast at.
    var wholeSatPerVb: UInt64 {
        guard self.isFinite, self > 1 else { return 1 }
        return UInt64(self.rounded(.down))
    }
    
    // Fee in whole satoshis for this rate over `vsize` virtual bytes, quoted at
    // the rate that will actually be broadcast.
    func feeSats(forVsize vsize: Double) -> Int {
        guard vsize.isFinite, vsize > 0 else { return 0 }
        return Int(self.wholeSatPerVb) * Int(vsize.rounded())
    }
}
