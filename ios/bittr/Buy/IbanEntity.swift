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
    // When the customer confirmed that this registration is made on their own
    // exclusive initiative — the precondition published T&C §2.5 puts on Bittr
    // providing any Service. ISO-8601, UTC, second precision.
    //
    // Optional on purpose: the synthesised Decodable initialiser ignores a
    // property's default value and throws on a missing key, and a throw here
    // loses every stored IBAN entity (CacheStore.decoded returns nil on a decode
    // failure). Optional decodes a pre-existing cache to nil instead — which is
    // also the truthful value for a registration made before this was collected.
    var initiativeConfirmedAt:String?
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
        self.initiativeConfirmedAt = dictionary["initiativeconfirmedat"] as? String
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
