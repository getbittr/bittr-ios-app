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
    
    var stableID: String? {
        switch self {
        case .onchain(let txID, _):
            return txID
        case .bolt11(let hash, _, _):
            return hash
        case .bolt11Jit(let hash, _, _, _, _):
            return hash
        case .spontaneous(let hash, _):
            return hash
        case .bolt12Offer(hash: let hash, preimage: _, secret: _, offerId: _, payerNote: _, quantity: _):
            return hash
        case .bolt12Refund(hash: let hash, preimage: _, secret: _, payerNote: _, quantity: _):
            return hash
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

    var isBolt12: Bool {
        switch self {
        case .bolt12Offer, .bolt12Refund:
            return true
        default:
            return false
        }
    }
    
}

extension PaymentDetails {
    
    // The key this payment's cached data is written under.
    var cacheID: String {
        return self.kind.stableID ?? self.id
    }
    
    // Every key that data might be found under: the stable one, then the
    // preimage, which is what versions before stableID wrote against.
    var cacheIDs: [String] {
        var ids = [self.cacheID]
        if let transactionID = self.kind.transactionID, transactionID != self.cacheID {
            ids.append(transactionID)
        }
        return ids
    }
}
