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
            let peers = try await LightningNodeService.shared.listPeers()
            var peerIsConnected = false
            for eachPeer in peers {
                if eachPeer.nodeId == EnvironmentConfig.lightningNodeId, eachPeer.isConnected {
                    peerIsConnected = true
                }
            }
            if peerIsConnected {
                print("Did successfully check peer connection.")
                return true
            } else {
                print("Not connected to peer.")
                return false
            }
        } catch {
            print("Error listing peers: \(error.localizedDescription)")
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
        let lightningPubKey = LightningNodeService.shared.nodeId()
        print(lightningPubKey)
        
        // Check peer connection.
        Task {
            await self.isConnectedToPeer()
            LightningNodeService.shared.listenForEvents()
        }
    }

}
