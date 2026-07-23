//
//  PaymentKind.swift
//  bittr
//
//  Created by Tom Melters on 7/22/26.
//

import UIKit
import LDKNode

extension PaymentKind {
    
    var transactionID: String? {
        switch self {
        case .onchain(let txID, _):
            return txID
        case .bolt11(_, let preimage, _):
            return preimage
        case .bolt11Jit(_, let preimage, _, _, _):
            return preimage
        case .spontaneous(_, let preimage):
            return preimage
        case .bolt12Offer(hash: _, preimage: let preimage, secret: _, offerId: _, payerNote: _, quantity: _):
            return preimage
        case .bolt12Refund(hash: _, preimage: let preimage, secret: _, payerNote: _, quantity: _):
            return preimage
        }
    }
    
    var isOnchain: Bool {
        switch self {
        case .onchain(_, _):
            return true
        default:
            return false
        }
    }
    
}
