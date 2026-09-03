//
//  BDKErrors.swift
//  bittr
//
//  Created by Tom Melters on 10/9/25.
//

import Foundation
import BitcoinDevKit

extension BitcoinDevKit.CreateTxError {
    
    func getErrorMessage() -> String {
        
        switch self {
            
        case .Descriptor(errorMessage: let errorMessage):
            return errorMessage
        case .Policy(errorMessage: let errorMessage):
            return errorMessage
        case .SpendingPolicyRequired(kind: let kind):
            return Language.getWord(withID: "SpendingPolicyRequired")
        case .Version0:
            return Language.getWord(withID: "Version0")
        case .Version1Csv:
            return Language.getWord(withID: "Version1Csv")
        case .LockTime(requested: let requested, required: let required):
            return Language.getWord(withID: "LockTime")
        case .RbfSequenceCsv(sequence: let sequence, csv: let csv):
            return Language.getWord(withID: "RbfSequenceCsv")
        case .FeeTooLow(required: let required):
            return Language.getWord(withID: "FeeTooLow").replacingOccurrences(of: "<required>", with: required)
        case .FeeRateTooLow(required: let required):
            return Language.getWord(withID: "FeeTooLow").replacingOccurrences(of: "<required>", with: required)
        case .NoUtxosSelected:
            return Language.getWord(withID: "NoUtxosSelected")
        case .OutputBelowDustLimit:
            // BDK's error carries only the offending output's index, not the dust
            // threshold, so there is no number to substitute here. (The old code
            // spliced the index into "<dustlimit>" without the angle brackets,
            // producing the nonsensical "dust limit of <0> satoshis".)
            return Language.getWord(withID: "OutputBelowDustLimit")
        case .ChangePolicyDescriptor:
            return Language.getWord(withID: "ChangePolicyDescriptor")
        case .CoinSelection(errorMessage: let errorMessage):
            return errorMessage
        case .InsufficientFunds(needed: let needed, available: let available):
            return Language.getWord(withID: "InsufficientFunds").replacingOccurrences(of: "<less>", with: "\(needed - available)")
        case .NoRecipients:
            return Language.getWord(withID: "NoRecipients")
        case .Psbt(errorMessage: let errorMessage):
            return errorMessage
        case .MissingKeyOrigin(key: let key):
            return Language.getWord(withID: "MissingKeyOrigin")
        case .UnknownUtxo(outpoint: let outpoint):
            return Language.getWord(withID: "UnknownUtxo")
        case .MissingNonWitnessUtxo(outpoint: let outpoint):
            return Language.getWord(withID: "MissingNonWitnessUtxo")
        case .MiniscriptPsbt(errorMessage: let errorMessage):
            return errorMessage
        case .PushBytesError:
            return Language.getWord(withID: "PushBytesError")
        case .LockTimeConversionError:
            return Language.getWord(withID: "LockTimeConversionError")
        }
    }

    /// A self-contained, consumer-friendly message for the errors a user can
    /// actually act on. Returns nil for internal/technical errors — and, via the
    /// default, for any future BDK case — so the caller falls back to a generic
    /// "we couldn't proceed" message rather than surfacing a cryptic string.
    func consumerFriendlyMessage() -> String? {
        switch self {
        case .InsufficientFunds(needed: let needed, available: let available):
            return Language.getWord(withID: "InsufficientFunds").replacingOccurrences(of: "<less>", with: "\(needed - available)")
        case .OutputBelowDustLimit:
            return Language.getWord(withID: "OutputBelowDustLimit")
        case .FeeTooLow(required: let required), .FeeRateTooLow(required: let required):
            return Language.getWord(withID: "FeeTooLow").replacingOccurrences(of: "<required>", with: required)
        default:
            return nil
        }
    }
}

extension BitcoinDevKit.EsploraError {
    
    func getErrorMessage() -> String {
        
        switch self {
            
        case .Minreq(errorMessage: let errorMessage):
            return errorMessage
        case .HttpResponse(status: _, errorMessage: _):
            return Language.getWord(withID: "EsploraHttpResponse")
        case .Parsing(errorMessage: let errorMessage):
            return errorMessage
        case .StatusCode(errorMessage: let errorMessage):
            return errorMessage
        case .BitcoinEncoding(errorMessage: let errorMessage):
            return errorMessage
        case .HexToArray(errorMessage: let errorMessage):
            return errorMessage
        case .HexToBytes(errorMessage: let errorMessage):
            return errorMessage
        case .TransactionNotFound:
            return Language.getWord(withID: "TransactionNotFound")
        case .HeaderHeightNotFound(height: let height):
            return Language.getWord(withID: "HeaderHeightNotFound")
        case .HeaderHashNotFound:
            return Language.getWord(withID: "HeaderHashNotFound")
        case .InvalidHttpHeaderName(name: let name):
            return Language.getWord(withID: "InvalidHttpHeaderName")
        case .InvalidHttpHeaderValue(value: let value):
            return Language.getWord(withID: "InvalidHttpHeaderValue")
        case .RequestAlreadyConsumed:
            return Language.getWord(withID: "RequestAlreadyConsumed")
        case .InvalidResponse:
            return Language.getWord(withID: "InvalidResponse")
        }
    }
}

extension BitcoinDevKit.AddressParseError {
    
    func getErrorMessage() -> String {
        
        switch self {
        case .Base58:
            return "[Base58]"
        case .Bech32:
            return "[Bech32]"
        case .WitnessVersion(errorMessage: let errorMessage):
            return errorMessage
        case .WitnessProgram(errorMessage: let errorMessage):
            return errorMessage
        case .UnknownHrp:
            return "[UnknownHrp]"
        case .LegacyAddressTooLong:
            return "[LegacyAddressTooLong]"
        case .InvalidBase58PayloadLength:
            return "[InvalidBase58PayloadLength]"
        case .InvalidLegacyPrefix:
            return "[InvalidLegacyPrefix]"
        case .NetworkValidation:
            return Language.getWord(withID: "wrongnetworkaddress")
        case .OtherAddressParseErr:
            return "[OtherAddressParseErr]"
        }
    }

    /// Every address parse failure is a user-input problem, so all map to a
    /// friendly message: wrong-network gets its own, everything else (incl. any
    /// future case) is simply "not a valid address".
    func consumerFriendlyMessage() -> String? {
        switch self {
        case .NetworkValidation:
            return Language.getWord(withID: "wrongnetworkaddress")
        default:
            return Language.getWord(withID: "invalidbitcoinaddress")
        }
    }
}

extension BitcoinDevKit.ElectrumError {
    
    func getErrorMessage() -> String {
        
        switch self {
        case .IoError(errorMessage: let errorMessage):
            return errorMessage
        case .Json(errorMessage: let errorMessage):
            return errorMessage
        case .Hex(errorMessage: let errorMessage):
            return errorMessage
        case .Protocol(errorMessage: let errorMessage):
            return errorMessage
        case .Bitcoin(errorMessage: let errorMessage):
            return errorMessage
        case .AlreadySubscribed:
            return "Already subscribed."
        case .NotSubscribed:
            return "Not subscribed."
        case .InvalidResponse(errorMessage: let errorMessage):
            return errorMessage
        case .Message(errorMessage: let errorMessage):
            return errorMessage
        case .InvalidDnsNameError(domain: let domain):
            return "Invalid DNS name."
        case .MissingDomain:
            return "Missing domain."
        case .AllAttemptsErrored:
            return "All attempts errored."
        case .SharedIoError(errorMessage: let errorMessage):
            return errorMessage
        case .CouldntLockReader:
            return "Couldn’t take a lock on the reader mutex."
        case .Mpsc:
            return "MPSC: Broken IPC communication channel."
        case .CouldNotCreateConnection(errorMessage: let errorMessage):
            return errorMessage
        case .RequestAlreadyConsumed:
            return "Request already consumed."
        }
    }
}

extension BitcoinDevKit.CannotConnectError {
    
    func getErrorMessage() -> String {
        
        switch self {
        case .Include(height: let height):
            return "Cannot connect (height: \(height))."
        }
    }
}
