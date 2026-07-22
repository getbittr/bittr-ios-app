//
//  BittrWallet.swift
//  bittr
//
//  Created by Tom Melters on 24/06/2023.
//

import UIKit
import LDKNode

class BittrWallet: NSObject {

    // Balance
    var satoshisLightning:Int = 0
    var satoshisOnchain:Int = 0
    var satoshisOnchainSpendable:Int = 0
    
    // Channels
    var lightningChannels = [ChannelDetails]()
    
    // Transactions
    var allTransactions = [PaymentDetails]()
    
    // Blockchain
    var currentHeight:Int?
    var onchainAddresses:[OnchainAddress]?
    var onchainAddressesVerified:Bool = false
    
    // Currency conversion
    var valueInEUR:CGFloat?
    var valueInCHF:CGFloat?
    
    // Bittr signup
    var ibanEntities = [IbanEntity]()
    
    // Get conversion rate
    func getCorrectBitcoinValue() -> BitcoinValue {
        
        let bitcoinValue = BitcoinValue()
        bitcoinValue.currentValue = self.valueInEUR ?? 0.0
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            bitcoinValue.currentValue = self.valueInCHF ?? 0.0
            bitcoinValue.chosenCurrency = "CHF"
            bitcoinValue.apiUrl = "https://getbittr.com/api/price/btc/historical/chf"
        }
        
        return bitcoinValue
    }
}
