//
//  String.swift
//  bittr
//
//  Created by Tom Melters on 2/24/26.
//

import UIKit

extension String {
    
    func isValidEmail() -> Bool {
        
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: self)
    }
    
    func addSpaces() -> String {
        
        var balanceValue = self
        if balanceValue.fixDecimals().contains(Locale.current.decimalSeparator!) {
            balanceValue = String(self.fixDecimals().split(separator: Locale.current.decimalSeparator!)[0])
        }
        
        switch balanceValue.count {
        case 4:
            balanceValue = balanceValue[0] + " " + balanceValue[1..<4]
        case 5:
            balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5]
        case 6:
            balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6]
        case 7:
            balanceValue = balanceValue[0] + " " + balanceValue[1..<4] + " " + balanceValue[4..<7]
        case 8:
            balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5] + " " + balanceValue[5..<8]
        case 9:
            balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6] + " " + balanceValue[6..<9]
        default:
            balanceValue = balanceValue[0..<balanceValue.count]
        }
        
        if self.fixDecimals().contains(Locale.current.decimalSeparator!) {
            var decimals = String(self.fixDecimals().split(separator: Locale.current.decimalSeparator!)[1])
            if decimals.count == 1 {
                decimals += "0"
            } else if decimals.count > 2 {
                decimals = decimals[0..<2]
            }
            return (balanceValue + Locale.current.decimalSeparator! + decimals)
        } else {
            return balanceValue
        }
    }
    
    func fixDecimals() -> String {
        return self.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)
    }
    
    func toNumber() -> CGFloat {
        
        let formatter = NumberFormatter()
        formatter.decimalSeparator = Locale.current.decimalSeparator!
        
        if formatter.number(from: self.fixDecimals()) == nil {
            return 0
        } else {
            return CGFloat(truncating: formatter.number(from: self.fixDecimals())!)
        }
    }
}
