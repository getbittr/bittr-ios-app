//
//  String.swift
//  bittr
//
//  Created by Tom Melters on 2/24/26.
//

import UIKit
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

        // Group with a non-breaking space. A plain space is a legal line-break
        // opportunity, so a wrapping label could split "1 213" into "1" and
        // "213" on separate lines and read as two numbers. Output is display
        // only — no call site parses it back — so the narrower space is safe.
        let separator = "\u{00A0}"

        switch balanceValue.count {
        case 4:
            balanceValue = balanceValue[0] + separator + balanceValue[1..<4]
        case 5:
            balanceValue = balanceValue[0..<2] + separator + balanceValue[2..<5]
        case 6:
            balanceValue = balanceValue[0..<3] + separator + balanceValue[3..<6]
        case 7:
            balanceValue = balanceValue[0] + separator + balanceValue[1..<4] + separator + balanceValue[4..<7]
        case 8:
            balanceValue = balanceValue[0..<2] + separator + balanceValue[2..<5] + separator + balanceValue[5..<8]
        case 9:
            balanceValue = balanceValue[0..<3] + separator + balanceValue[3..<6] + separator + balanceValue[6..<9]
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
    
    func inGroupsOfFour() -> String {
        
        // A plain space, so a wrapping label breaks between groups.
        var grouped = ""
        for (index, character) in self.enumerated() {
            if index > 0, index % 4 == 0 {
                grouped += " "
            }
            grouped.append(character)
        }
        return grouped
    }
    
    func inGroupsOfFour(width:CGFloat, lines:Int = .max, font:UIFont, color:UIColor) -> NSAttributedString {
        
        // Every character in a monospaced font is as wide as a zero.
        let characterWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        let groupsPerLine = max(2, Int((width + characterWidth) / (5 * characterWidth)))
        
        var groups = self.inGroupsOfFour().components(separatedBy: " ")
        var ellipsisIndex:Int?
        if (groups.count - 1) / groupsPerLine >= lines {
            // The last line keeps groups from both ends, with an ellipsis in the slot of the groups in between.
            let tailCount = (groupsPerLine - 1) / 2
            let headCount = groupsPerLine * lines - 1 - tailCount
            ellipsisIndex = headCount
            // The tail is grouped from the end, so its last group is never cut short.
            let tail = String(self.suffix(tailCount * 4)).inGroupsOfFour().components(separatedBy: " ")
            groups = Array(groups.prefix(headCount)) + ["\u{2026}"] + tail
        }
        
        // Left-aligned, so every line's groups stay in the same columns.
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        let attributes:[NSAttributedString.Key:Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle]
        let shortened = NSMutableAttributedString()
        for (index, group) in groups.enumerated() {
            if index > 0 {
                shortened.append(NSAttributedString(string: index % groupsPerLine == 0 ? "\n" : " ", attributes: attributes))
            }
            shortened.append(NSAttributedString(string: group, attributes: attributes))
        }
        
        if let ellipsisIndex {
            // Centre the ellipsis in a four-character slot, so the groups after it stay in their columns.
            let ellipsisWidth = ("\u{2026}" as NSString).size(withAttributes: [.font: font]).width
            let padding = (4 * characterWidth - ellipsisWidth) / 2
            let ellipsisLocation = ellipsisIndex * 5
            shortened.addAttribute(.kern, value: padding, range: NSRange(location: ellipsisLocation - 1, length: 1))
            shortened.addAttribute(.kern, value: padding, range: NSRange(location: ellipsisLocation, length: 1))
        }
        
        return shortened
    }
    
    func fixDecimals() -> String {
        return self.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)
    }
    
    // Reads a value written in machine format:
    // An API response, or a number this app cached earlier.
    func parsedNumber() -> Decimal? {
        
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        var body = Substring(trimmed)
        var isNegative = false
        if let sign = body.first, sign == "-" || sign == "+" {
            isNegative = (sign == "-")
            body = body.dropFirst()
        }
        
        // Digits, at most one separator, and at least one digit.
        guard body.allSatisfy({ $0.isDecimalDigit || NumberParsing.separators.contains($0) }),
              body.contains(where: { $0.isDecimalDigit }),
              body.filter({ NumberParsing.separators.contains($0) }).count <= 1
        else { return nil }
        
        // Decimal parses exactly, so an 8-decimal bitcoin amount survives the
        // conversion to satoshis without picking up a binary rounding error.
        guard let magnitude = Decimal(string: String(body).replacingOccurrences(of: ",", with: "."),
                                      locale: NumberParsing.posix)
        else { return nil }
        
        return isNegative ? -magnitude : magnitude
    }
    
    // Reads an amount a person typed into a text field.
    func parsedUserAmount(allowingFraction: Bool = true) -> Decimal? {
        
        // Grouping separators the user (or this app's own display formatting) may have typed.
        let stripped = self.components(separatedBy: NumberParsing.groupingCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        
        var characters = Array(stripped)
        let separatorPositions = characters.indices.filter { NumberParsing.separators.contains(characters[$0]) }
        
        // Decide which separator is the decimal point.
        let decimalPosition:Int?
        
        if !allowingFraction || separatorPositions.isEmpty {
            // A whole-satoshi field has no decimal point by definition.
            decimalPosition = nil
        } else if separatorPositions.count == 1 {
            // Only one decimal position has been detected.
            let position = separatorPositions[0]
            // Number of digits behind the decimal point.
            let fractionDigits = characters.count - position - 1
            // Is the decimal the locale separator?
            let isLocaleSeparator = String(characters[position]) == (Locale.current.decimalSeparator ?? ".")
            
            if isLocaleSeparator || fractionDigits != 3 {
                decimalPosition = position
            } else {
                decimalPosition = NumberParsing.groupsAreWellFormed(characters, groupingAt: [position], decimalAt: nil) ? nil : position
            }
        } else if Set(separatorPositions.map { characters[$0] }).count > 1 {
            // Both separator characters appear, so the last one is the decimal
            // point and the other kind groups: "1,234.56" and "1.234,56".
            decimalPosition = separatorPositions[separatorPositions.count - 1]
        } else {
            // The same separator repeated can only be grouping — a number has at
            // most one decimal point. "1.234.567" is a million and a bit;
            // "1.2.3" is not a number at all, and the check below rejects it.
            decimalPosition = nil
        }
        
        let groupingPositions = separatorPositions.filter { $0 != decimalPosition }
        guard NumberParsing.groupsAreWellFormed(characters, groupingAt: groupingPositions, decimalAt: decimalPosition) else { return nil }
        
        if let decimalPosition = decimalPosition { characters[decimalPosition] = "." }
        if !groupingPositions.isEmpty {
            let grouping = Set(groupingPositions)
            characters = characters.enumerated().filter { !grouping.contains($0.offset) }.map(\.element)
        }
        
        return String(characters).parsedNumber()
    }
    
    // Back-compatible shim over parsedNumber().
    func toNumber() -> CGFloat {
        guard let parsed = self.parsedNumber() else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: parsed).doubleValue)
    }
    
    func getInvoiceHash() -> String? {
        return self.bolt11Invoice()?.paymentHash().lowercased()
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
        
        // Add HTML elements.
        let thisColor:String = CacheManager.darkModeIsOn() ? "255, 255, 255" : "0, 0, 0"
        let thisText:String = self.replacingOccurrences(of: "\n", with: "<br>").replacingOccurrences(of: "<b>", with: "</span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: 16px; color: rgb(\(thisColor)); line-height: 1.28\">").replacingOccurrences(of: "</b>", with: "</span><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16px; color: rgb(\(thisColor)); line-height: 1.28\">")
        let htmlString:String = "<center><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16px; color: rgb(\(thisColor)); line-height: 1.28;\">\(thisText)</span></center>"
        
        // Create plain-text fallback.
        let plainFallback = NSAttributedString(string: self
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: ""))
        
        // Parse HTML.
        guard let htmlData = htmlString.data(using: .unicode),
              let attributedText = try? NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
        else { return plainFallback }
        
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
        
        let targetSize:CGFloat = 1080
        let data = self.data(using: .utf8)
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let extent = outputImage.extent.integral
        guard let cgImage = CIContext().createCGImage(outputImage, from: extent) else { return nil }
        
        // Every module gets the same whole number of pixels, so the box below can sit exactly on module edges.
        let moduleCount = Int(extent.width)
        let modulePixels = max(1, Int(targetSize) / moduleCount)
        let size = CGFloat(moduleCount * modulePixels)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        
        return renderer.image { context in
            
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: cgImage).draw(in: CGRect(x: 0, y: 0, width: size, height: size))
            
            guard let logo = UIImage(named: "logoorange32") else { return }
            
            // The box covers whole modules, odd or even like the code itself, so it centres on the grid.
            var logoModuleCount = Int(ceil(size * 0.13 / CGFloat(modulePixels)))
            if logoModuleCount % 2 != moduleCount % 2 {
                logoModuleCount += 1
            }
            let boxSize = CGFloat(logoModuleCount * modulePixels)
            let boxOrigin = CGFloat((moduleCount - logoModuleCount) / 2 * modulePixels)
            
            UIColor.white.setFill()
            UIRectFill(CGRect(x: boxOrigin, y: boxOrigin, width: boxSize, height: boxSize))
            
            let padding:CGFloat = 30
            context.cgContext.interpolationQuality = .high
            logo.draw(in: CGRect(x: boxOrigin + padding, y: boxOrigin + padding, width: boxSize - 2 * padding, height: boxSize - 2 * padding))
        }
    }
    
    func bolt12Offer() -> LDKNode.Offer? {
        guard self.lowercased().hasPrefix("lno") else { return nil }
        do {
            let offer = try LDKNode.Offer.fromStr(offerStr: self)
            return offer
        } catch {
            // Reached from isValidInvoice while parsing pasted/scanned input, so
            // keep the breadcrumb for a malformed lno string.
            Log.info("Could not generate BOLT12 offer.")
            return nil
        }
    }
}

// MARK: - Amounts

enum Bitcoin {
    
    // The 21 M supply, in satoshis.
    static let maximumSatoshis = 2_100_000_000_000_000
    
    static let satoshisPerBitcoin = 100_000_000
}

private enum NumberParsing {
    
    // The two characters that act as a decimal point.
    static let separators: Set<Character> = [".", ","]
    
    // Characters that act as a thousands separator.
    static let groupingCharacters = CharacterSet(charactersIn: "\u{0020}\u{00A0}\u{202F}\u{2009}'\u{2019}")
    
    // Parsing against a fixed locale keeps the result independent of the device's region settings.
    static let posix = Locale(identifier: "en_US_POSIX")
    
    // Whether the separators really do divide the number into thousands.
    static func groupsAreWellFormed(_ characters:[Character], groupingAt positions:[Int], decimalAt decimalPosition:Int?) -> Bool {
        guard !positions.isEmpty else { return true }
        
        let end = decimalPosition ?? characters.count
        
        // The leading group is the only one allowed to be short.
        guard positions[0] >= 1, positions[0] <= 3 else { return false }
        
        for (index, position) in positions.enumerated() {
            let nextSeparator = index + 1 < positions.count ? positions[index + 1] : end
            guard nextSeparator - position - 1 == 3 else { return false }
        }
        
        return true
    }
}

private extension Character {
    var isDecimalDigit: Bool {
        return ("0"..."9").contains(self)
    }
}

extension Decimal {
    
    // Rounds a value that is already denominated in satoshis to a whole, in-range `Int`.
    func satoshis() -> Int? {
        guard !self.isNaN, self >= 0 else { return nil }
        
        var rounded = Decimal()
        var value = self
        NSDecimalRound(&rounded, &value, 0, .plain)
        
        guard rounded <= Decimal(Bitcoin.maximumSatoshis) else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }
    
    // Converts a bitcoin amount to whole satoshis.
    func satoshisFromBitcoin() -> Int? {
        return (self * Decimal(Bitcoin.satoshisPerBitcoin)).satoshis()
    }
}
