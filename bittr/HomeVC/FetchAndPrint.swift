//
//  FetchAndPrint.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import Sentry

extension UIViewController {
    
    func isConnectedToPeer() async -> Bool {
        
        do {
            let peers = try await BitcoinManager.shared.listPeers()
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
        } catch {
            Log.info("Error listing peers: \(error.localizedDescription)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "FetchAndPrint row 34", key: "context")
                }
            }
            return false
        }
    }
}

extension HomeViewController {
    
    func fetchAndPrintPeers() {
        
        // Print nodeID.
        if let lightningPubKey = BitcoinManager.shared.nodeId() {
            print(lightningPubKey)
        }
        
        // Check peer connection.
        Task {
            await self.isConnectedToPeer()
            BitcoinManager.shared.listenForEvents()
        }
    }

}
