//
//  LDKManager.swift
//  bittr
//
//  Created by Tom Melters on 9/7/26.
//

import UIKit
import LightningDevKit

extension String {
    
    func getLightningFeesInSatoshis(amountMsat:UInt64? = nil) -> Int? {
        guard let invoice = Bindings.Bolt11Invoice.fromStr(s: self).getValue() else { return nil }
        
        let invoicePaymentResult:Bindings.Result_C3Tuple_ThirtyTwoBytesRecipientOnionFieldsRouteParametersZNoneZ
        if invoice.amountMilliSatoshis() != nil {
            // Standard invoice.
            invoicePaymentResult = Bindings.paymentParametersFromInvoice(invoice: invoice)
        } else {
            // Zero amount invoice, needs an amount.
            guard let amountMsat else { return nil }
            invoicePaymentResult = Bindings.paymentParametersFromZeroAmountInvoice(invoice: invoice, amountMsat: amountMsat)
        }
        
        guard let (_, _, tryRouteParams) = invoicePaymentResult.getValue() else { return nil }
        let maximumRoutingFeesMsat:Int = Int(tryRouteParams.getMaxTotalRoutingFeeMsat() ?? 0)
        let maximumRoutingFeesSat:Int = maximumRoutingFeesMsat/1000
        return maximumRoutingFeesSat
    }
}
