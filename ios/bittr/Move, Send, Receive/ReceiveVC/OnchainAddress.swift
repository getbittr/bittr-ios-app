//
//  OnchainAddress.swift
//  bittr
//
//  Created by Tom Melters on 4/7/26.
//

import Foundation

class OnchainAddress: NSObject, Codable {
    
    var onchainAddress:String = ""
    var addressIndex:Int = 0
    var hasBeenUsed:Bool = false
    
    
    convenience init?(legacyDictionary dictionary:NSDictionary) {
        guard let onchainAddress = dictionary["onchainAddress"] as? String,
              let addressIndex = dictionary["addressIndex"] as? Int,
              let hasBeenUsed = dictionary["hasBeenUsedByBittr"] as? Bool
        else { return nil }
        
        self.init()
        self.onchainAddress = onchainAddress
        self.addressIndex = addressIndex
        self.hasBeenUsed = hasBeenUsed
    }
}

extension [OnchainAddress] {
    
    func inPoolOrder() -> [OnchainAddress] {
        let onchainAddresses = self.sorted { $0.addressIndex < $1.addressIndex }
        
        for (position, eachAddress) in onchainAddresses.enumerated() where eachAddress.addressIndex != position {
            Log.info("Cached onchain addresses are not contiguous from zero; discarding the cached pool.")
            return [OnchainAddress]()
        }
        
        return onchainAddresses
    }
    
    func toStrings() -> [String] {
        return self.map { $0.onchainAddress }
    }
}

extension [NSDictionary] {
    
    func toLegacyAddresses() -> [OnchainAddress]? {
        var onchainAddresses = [OnchainAddress]()
        for eachDictionary in self {
            guard let address = OnchainAddress(legacyDictionary: eachDictionary) else {
                Log.info("Cached onchain addresses could not be read; discarding the cached pool.")
                return nil
            }
            onchainAddresses += [address]
        }
        return onchainAddresses
    }
}
