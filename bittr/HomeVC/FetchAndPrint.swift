//
//  FetchAndPrint.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension HomeViewController {

    func fetchAndPrintChannels() {
        
        Task {
            do {
                let channels = try await LightningNodeService.shared.listChannels()
                print("Channels: \(channels)")
            } catch {
                print("Error listing channels: \(error.localizedDescription)")
            }
        }
    }
    
    
    func fetchAndPrintPeers() {
        
        Task {
            do {
                let peers = try await LightningNodeService.shared.listPeers()
                if peers.count == 1 {
                    if peers[0].isConnected == true {
                        print("Did successfully check peer connection.")
                    } else {
                        print("Not connected to peer.")
                    }
                } else {
                    print("Not connected to peer.")
                }
            } catch {
                print("Error listing peers: \(error.localizedDescription)")
            }
        }
    }
    
    
    func fetchAndPrintPayments() {
        
        Task {
            do {
                let payments = try await LightningNodeService.shared.listPayments()
                print("Payments: \(payments)")
            } catch {
                print("Error listing peers: \(error.localizedDescription)")
            }
        }
    }

}
