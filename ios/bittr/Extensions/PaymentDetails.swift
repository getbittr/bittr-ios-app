//
//  PaymentDetails.swift
//  bittr
//
//  Created by Tom Melters on 7/22/26.
//

import UIKit
import LDKNode

extension PaymentDetails {
    
    func hasSucceeded() -> Bool {
        if self.status == .succeeded {
            return true
        } else {
            return false
        }
    }
    
    func isPendingOutbound() -> Bool {
        if self.status == .pending && self.direction == .outbound && (Int((self.amountMsat ?? 0)/1000) > 0 || Int((self.feePaidMsat ?? 0)/1000) > 0) {
            return true
        } else {
            return false
        }
    }
    
    func isUnconfirmedOnchainInbound() -> Bool {
        if self.status == .pending && self.kind.isOnchain && self.direction == .inbound {
            return true
        } else {
            return false
        }
    }
}
