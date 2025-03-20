//
//  FetchAndPrint.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension HomeViewController {
    
    func fetchAndPrintPeers() {
        let lightningPubKey = LightningNodeService.shared.nodeId()
        print(lightningPubKey)
        Task {
            do {
                let peers = try await LightningNodeService.shared.listPeers()
                if peers.count == 1 {
                    if peers[0].isConnected == true {
                        Task {
                            do {
                                let result = try await BoltzRefund.tryBoltzRefund()
                                print("Result: \(result)")
                            } catch {
                                print("Error: \(error)")
                            }
                        }

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
                } else {
                    print("Not connected to peer.")
                    DispatchQueue.main.async {
                        LightningNodeService.shared.listenForEvents()
                    }
                }
            } catch {
                print("Error listing peers: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    LightningNodeService.shared.listenForEvents()
                }
            }
        }
    }

}
