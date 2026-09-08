//
//  IbanEntity.swift
//  bittr
//
//  Created by Tom Melters on 24/06/2023.
//

import UIKit

class IbanEntity: NSObject, Codable {
    
    var yourIbanNumber = ""
    var yourEmail = ""
    var ourIbanNumber = ""
    var ourName = "BITTR AG"
    var yourUniqueCode = ""
    var order = 0
    var id = ""
    var emailToken = ""
    var ourSwift = ""
    var lightningAddressUsername = ""
    // Payout mode for this deposit code: "lightning" or "onchain".
    // Empty until the backend reports it (registration / deposit_code / payment-mode endpoints).
    var paymentMode = ""
}

extension IbanEntity {
    
    convenience init(id:String, legacyDictionary dictionary:NSDictionary) {
        self.init()
        self.id = id
        self.order = dictionary["order"] as? Int ?? 0
        self.yourIbanNumber = dictionary["youriban"] as? String ?? ""
        self.yourEmail = dictionary["youremail"] as? String ?? ""
        self.yourUniqueCode = dictionary["yourcode"] as? String ?? ""
        self.ourIbanNumber = dictionary["ouriban"] as? String ?? ""
        self.ourName = dictionary["ourname"] as? String ?? "BITTR AG"
        self.emailToken = dictionary["token"] as? String ?? ""
        self.ourSwift = dictionary["ourswift"] as? String ?? ""
        self.lightningAddressUsername = dictionary["lightningaddressusername"] as? String ?? ""
        self.paymentMode = dictionary["paymentmode"] as? String ?? ""
    }
    
    static func fromLegacyDeviceDictionary(_ device:NSDictionary) -> [IbanEntity] {
        
        var ibans = [IbanEntity]()
        for (_, client) in device {
            guard let client = client as? NSDictionary,
                  let legacyIbans = client["ibans"] as? NSDictionary else { continue }
            
            for (identifier, values) in legacyIbans {
                guard let identifier = identifier as? String,
                      let values = values as? NSDictionary else { continue }
                ibans += [IbanEntity(id: identifier, legacyDictionary: values)]
            }
        }
        
        return ibans.sorted { $0.order < $1.order }
    }
}
