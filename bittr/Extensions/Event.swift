//
//  Event.swift
//  bittr
//
//  Created by Tom Melters on 3/12/26.
//

import LDKNode

extension LDKNode.Event {
    
    func isPaymentFailed() -> Bool {
        switch self {
        case .paymentFailed(paymentId: _, paymentHash: _, reason: _): return true
        default: return false
        }
    }
}
