//
//  String.swift
//  bittr
//
//  Created by Tom Melters on 2/24/26.
//

import UIKit
import LightningDevKit
import LDKNode

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
    
    func getInvoiceHash() -> String? {
        let result = Bolt11Invoice.fromStr(s: self)
        if result.isOk() {
            if let invoice = result.getValue() {
                print("Invoice parsed successfully: \(invoice)")
                let paymentHash:[UInt8] = invoice.paymentHash()!
                let hexString = paymentHash.map { String(format: "%02x", $0) }.joined()
                return hexString
            } else {
                return nil
            }
        } else if let error = result.getError() {
            Log.info("Failed to parse invoice: \(error)")
            return nil
        } else {
            return nil
        }
    }
    
    var length: Int {
        return count
    }

    subscript (i: Int) -> String {
        return self[i ..< i + 1]
    }

    func substring(fromIndex: Int) -> String {
        return self[min(fromIndex, length) ..< length]
    }

    func substring(toIndex: Int) -> String {
        return self[0 ..< max(0, toIndex)]
    }

    subscript (r: Range<Int>) -> String {
        let range = Range(uncheckedBounds: (lower: max(0, min(length, r.lowerBound)),
                                            upper: min(length, max(0, r.upperBound))))
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(start, offsetBy: range.upperBound - range.lowerBound)
        return String(self[start ..< end])
    }
    
    func attributed() -> NSAttributedString {
        
        let thisColor:String = {
            if CacheManager.darkModeIsOn() {
                return "255, 255, 255"
            } else {
                return "0, 0, 0"
            }
        }()
        
        let thisText:String = self.replacingOccurrences(of: "\n", with: "<br>").replacingOccurrences(of: "<b>", with: "</span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: 16px; color: rgb(\(thisColor)); line-height: 1.28\">").replacingOccurrences(of: "</b>", with: "</span><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16px; color: rgb(\(thisColor)); line-height: 1.28\">")
        
        let htmlString:String = "<center><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16px; color: rgb(\(thisColor)); line-height: 1.28;\">\(thisText)</span></center>"
        
        guard let htmlData = htmlString.data(using: .unicode) else { return NSAttributedString() }
        
        let attributedText = try! NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
        
        return attributedText
    }
    
    func toQRCode() -> (image:UIImage, width:Int)? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(self.utf8)
        filter.setValue(data, forKey: "inputMessage")
        
        guard let outputImage = filter.outputImage, let cgimg = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        
        let moduleWidth = Int(outputImage.extent.width)
        
        return (image: UIImage(cgImage: cgimg), width: moduleWidth)
    }
    
    func toBigQRCode() -> UIImage? {
            
        let data = self.data(using: .utf8)
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let extent = outputImage.extent.integral
        let scale = min(1080 / extent.width, 1080 / extent.height)
        
        let width = extent.width * scale
        let height = extent.height * scale
        
        let cs = CGColorSpaceCreateDeviceGray()
        
        guard let bitmap = CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(outputImage, from: extent) else { return nil }
        
        bitmap.interpolationQuality = .none
        bitmap.scaleBy(x: scale, y: scale)
        bitmap.draw(cgImage, in: extent)
        
        guard let scaledImage = bitmap.makeImage() else { return nil }
        
        return UIImage(cgImage: scaledImage)
    }
    
    func bolt12Offer() -> LDKNode.Offer? {
        if self.lowercased().hasPrefix("lno") {
            do {
                let offer = try LDKNode.Offer.fromStr(offerStr: self)
                return offer
            } catch {
                Log.info("Could not generate BOLT12 offer.")
                return nil
            }
        } else {
            return nil
        }
    }
}
