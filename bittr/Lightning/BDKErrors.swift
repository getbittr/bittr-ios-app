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
        case .OutputBelowDustLimit(index: let index):
            return Language.getWord(withID: "OutputBelowDustLimit").replacingOccurrences(of: "dustlimit", with: "\(index)")
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
}

extension BitcoinDevKit.EsploraError {
    
    func getErrorMessage() -> String {
        
        switch self {
            
        case .Minreq(errorMessage: let errorMessage):
            return errorMessage
        case .HttpResponse(status: let status, errorMessage: let errorMessage):
            return errorMessage
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
            return "[NetworkValidation]"
        case .OtherAddressParseErr:
            return "[OtherAddressParseErr]"
        }
    }
}
