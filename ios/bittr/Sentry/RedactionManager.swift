//
//  RedactionManager.swift
//  bittr
//
//  Created by Tom Melters on 8/3/26.
//

import UIKit

private enum Redaction {
    
    static let patterns:[String] = [
        
        // Lightning invoice, mainnet through regtest.
        #"(?i)(?<![a-z0-9])ln(?:bcrt|bc|tbs|tb|sb)[0-9]*[munp]?1[02-9ac-hj-np-z]{50,}"#,
        
        // LNURL.
        #"(?i)(?<![a-z0-9])lnurl1[02-9ac-hj-np-z]{10,}"#,
        
        // Extended public key. Hands over every address the wallet will ever
        // derive, so it matters more than any single one of them.
        #"(?<![A-Za-z0-9])[xyztuv]pub[1-9A-HJ-NP-Za-km-z]{50,}"#,
        
        // Bech32 onchain address.
        #"(?i)(?<![a-z0-9])(?:bcrt|bc|tb)1[02-9ac-hj-np-z]{25,71}"#,
        
        // Legacy base58 onchain address.
        #"(?<![A-Za-z0-9])[13mn2][1-9A-HJ-NP-Za-km-z]{25,34}(?![A-Za-z0-9])"#,
        
        // Node pubkey at 66 characters; txid, preimage and payment hash at 64.
        #"(?<![A-Fa-f0-9])[A-Fa-f0-9]{64,66}(?![A-Fa-f0-9])"#,
        
        // IBAN, written either compactly or in the usual groups of four.
        #"(?<![A-Za-z0-9])[A-Z]{2}[0-9]{2}(?:\s?[A-Z0-9]{2,4}){2,8}(?![A-Za-z0-9])"#,
        
        // Email address, which also covers a lightning address.
        #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        
        // Amounts, in bitcoin and in fiat. Unlike the pattern this replaces,
        // these need their unit to be present, so a version number, an error
        // code or a row index survives to be read.
        #"(?i)\b[0-9]+(?:[.,][0-9]+)?\s*(?:btc|sats?|satoshis?)\b"#,
        #"(?i)\b[0-9]+(?:[.,][0-9]+)?\s*(?:eur|usd|gbp)\b"#,
        #"[€$£]\s?[0-9]+(?:[.,][0-9]+)?"#,
        
        // A bitcoin amount written on its own, recognised by satoshi precision.
        #"\b[0-9]+\.[0-9]{8}\b"#
    ]
    
    static let expressions:[NSRegularExpression] = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    
    static let wordExpression = try? NSRegularExpression(pattern: #"[A-Za-z]+"#)
    
    static let bip39Words:Set<String> = Set(MnemonicWordListEN)
    
    static let minimumMnemonicWords = 12
}

extension String {
    
    /// Strips the values that would tell us who someone is or what they hold.
    func redactSensitiveValues() -> String {
        
        // Before the patterns run, so the replacements they insert cannot break
        // a phrase into runs too short to notice.
        var redacted = self.redactMnemonicPhrases()
        
        for expression in Redaction.expressions {
            redacted = expression.stringByReplacingMatches(
                in: redacted,
                range: NSRange(location: 0, length: (redacted as NSString).length),
                withTemplate: "[redacted]"
            )
        }
        
        return redacted
    }
    
    /// A recovery phrase is the one thing that must never reach us, and it is
    /// made of ordinary words, so no pattern describes it. Look instead for a
    /// long enough run of consecutive words that all belong to the BIP39 list.
    private func redactMnemonicPhrases() -> String {
        
        guard let wordPattern = Redaction.wordExpression else { return self }
        
        let text = self as NSString
        let words = wordPattern.matches(in: self, range: NSRange(location: 0, length: text.length))
        
        var phraseRanges = [NSRange]()
        var runStart:Int?
        var runEnd = 0
        var runLength = 0
        
        func closeRun() {
            if let runStart, runLength >= Redaction.minimumMnemonicWords {
                phraseRanges += [NSRange(location: runStart, length: runEnd - runStart)]
            }
            runStart = nil
            runLength = 0
        }
        
        for word in words {
            if Redaction.bip39Words.contains(text.substring(with: word.range).lowercased()) {
                if runStart == nil { runStart = word.range.location }
                runEnd = word.range.location + word.range.length
                runLength += 1
            } else {
                closeRun()
            }
        }
        closeRun()
        
        guard !phraseRanges.isEmpty else { return self }
        
        // Back to front, so each range still points where it did when found.
        let redacted = NSMutableString(string: self)
        for phraseRange in phraseRanges.reversed() {
            redacted.replaceCharacters(in: phraseRange, with: "[redacted]")
        }
        
        return redacted as String
    }
    
    func redactURL() -> String {
        // Regex pattern to catch URLs (both http and https)
        let pattern = #"(https?:\/\/[^\s]+)"#
        return self.replacingOccurrences(of: pattern, with: "[redacted URL]", options: .regularExpression)
    }
    
    func redactURLIdentifiers() -> String {
        
        // Drop any query and fragment wholesale.
        var url = self
        if let queryStart = url.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            url = String(url[url.startIndex..<queryStart])
        }
        
        return url
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { pathSegment in
                let isIdentifier = pathSegment.count >= 20 && pathSegment.allSatisfy { $0.isLetter || $0.isNumber }
                return isIdentifier ? "[redacted]" : String(pathSegment)
            }
            .joined(separator: "/")
    }
    
}
