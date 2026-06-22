//
//  IbanEntity.swift
//  bittr
//
//  Created by Tom Melters on 24/06/2023.
//

import UIKit

class IbanEntity: NSObject {
    
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
