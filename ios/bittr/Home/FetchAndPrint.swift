//
//  FetchAndPrint.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
    
func isConnectedToPeer() -> Bool {
    
    let peers = BitcoinManager.shared.listPeers()
    var peerIsConnected = false
    for eachPeer in peers where eachPeer.nodeId == EnvironmentConfig.lightningNodeId && eachPeer.isConnected {
        peerIsConnected = true
    }
    
    Log.info(peerIsConnected ? "Did successfully check peer connection." : "Not connected to peer.")
    return peerIsConnected
}

extension HomeViewController {
    
    func fetchAndPrintPeers() {
        
        // Check peer connection.
        _ = isConnectedToPeer()
        BitcoinManager.shared.listenForEvents()
    }

}
