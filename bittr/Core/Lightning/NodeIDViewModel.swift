//
//  NodeIDViewModel.swift
//  bittr
//
//  Created by Tom Melters on 25/07/2023.
//

import Foundation

class NodeIDViewModel: ObservableObject {
    
    func signMessage(message: String) async throws -> String {
        do {
            let signedMessage = try await LightningNodeService.shared.signMessage(message: message)
            return signedMessage
        } catch {
            throw error
        }
    }
}
