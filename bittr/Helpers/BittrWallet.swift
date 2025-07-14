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
    
    // Channels
    var lightningChannels = [ChannelDetails]()
    var bittrChannel:Channel?
    
    // Blockchain
    var currentHeight:Int?
    
    // Currency conversion
    var valueInEUR:CGFloat?
    var valueInCHF:CGFloat?
    
    // Bittr signup
    var ibanEntities = [IbanEntity]()
    
}
