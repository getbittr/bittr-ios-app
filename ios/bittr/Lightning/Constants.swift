//
//  Constants.swift
//  bittr
//
//  Created by Tom Melters on 18/07/2023.
//

import Foundation

struct Constants {
    
    struct Config {

        struct EsploraServerURLNetwork {
            struct Bitcoin {
                static let bitcoin_blockstream = "https://blockstream.info/api"
                static let bitcoin_mempoolspace = "https://mempool.space/api"
            }
            static let regtest = "https://esplora.regtest.getbittr.com/api"
            static let signet = "https://mutinynet.com/api"
            static let testnet = "https://mempool.space/testnet4/api"
        }
        
        struct RGSServerURLNetwork {
            static let bitcoin = "https://rapidsync.lightningdevkit.org/snapshot/"
            static let testnet = "https://rapidsync.lightningdevkit.org/testnet/snapshot/"
        }
        
    }
}
