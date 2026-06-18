//
//  FetchAndPrint.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import Sentry
    
func isConnectedToPeer() -> Bool {
    
    let peers = BitcoinManager.shared.listPeers()
    var peerIsConnected = false
    for eachPeer in peers {
        if eachPeer.nodeId == EnvironmentConfig.lightningNodeId, eachPeer.isConnected {
            peerIsConnected = true
        }
    }
    
    if peerIsConnected {
        Log.info("Did successfully check peer connection.")
        return true
    } else {
        Log.info("Not connected to peer.")
        return false
    }
}

extension HomeViewController {
    
    func fetchAndPrintPeers() {
        
        // Print nodeID.
        if let lightningPubKey = BitcoinManager.shared.nodeId() {
            print(lightningPubKey)
        }
        
        // Check peer connection.
        _ = isConnectedToPeer()
        BitcoinManager.shared.listenForEvents()
    }

}
