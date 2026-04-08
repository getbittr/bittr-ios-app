//
//  OnchainAddress.swift
//  bittr
//
//  Created by Tom Melters on 4/7/26.
//

import Foundation

class OnchainAddress: NSObject {
    
    var onchainAddress:String = ""
    var addressIndex:Int = 0
    var hasBeenUsedByBittr:Bool = false
    
}

extension [OnchainAddress] {
    
    func toDict() -> [NSDictionary] {
        
        var onchainAddresses = [NSDictionary]()
        
        for eachAddress in self {
            let thisAddress = NSMutableDictionary()
            thisAddress.setValue(eachAddress.onchainAddress, forKey: "onchainAddress")
            thisAddress.setValue(eachAddress.addressIndex, forKey: "addressIndex")
            thisAddress.setValue(eachAddress.hasBeenUsedByBittr, forKey: "hasBeenUsedByBittr")
            onchainAddresses += [thisAddress]
        }
        
        return onchainAddresses
    }
    
    func toStrings() -> [String] {
        
        var onchainAddresses = [String]()
        
        for eachAddress in self {
            onchainAddresses += [eachAddress.onchainAddress]
        }
        
        return onchainAddresses
    }
}

extension [NSDictionary] {
    
    func toAddresses() -> [OnchainAddress] {
        
        var onchainAddresses = [OnchainAddress]()
        
        for eachDictionary in self {
            guard
                let onchainAddress = eachDictionary["onchainAddress"] as? String,
                let addressIndex = eachDictionary["addressIndex"] as? Int,
                let hasBeenUsedByBittr = eachDictionary["hasBeenUsedByBittr"] as? Bool
            else { break }
            
            let thisAddress = OnchainAddress()
            thisAddress.onchainAddress = onchainAddress
            thisAddress.addressIndex = addressIndex
            thisAddress.hasBeenUsedByBittr = hasBeenUsedByBittr
            
            onchainAddresses += [thisAddress]
        }
        
        onchainAddresses.sort { address1, address2 in
            address1.addressIndex < address2.addressIndex
        }
        
        return onchainAddresses
    }
}
