//
//  FetchAndPrint.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import Sentry

extension HomeViewController {
    
    func fetchAndPrintPeers() {
        let lightningPubKey = LightningNodeService.shared.nodeId()
        print(lightningPubKey)
        Task {
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
                    DispatchQueue.main.async {
                        LightningNodeService.shared.listenForEvents()
                    }
                } else {
                    print("Not connected to peer.")
                    DispatchQueue.main.async {
                        LightningNodeService.shared.listenForEvents()
                    }
                }
            } catch {
                print("Error listing peers: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "FetchAndPrint row 40", key: "context")
                    }
                    LightningNodeService.shared.listenForEvents()
                }
            }
        }
    }

}
