//
//  BittrService.swift
//  bittr
//
//  Created by Tom Melters on 07/11/2023.
//

import Foundation

class BittrService {

    static let shared = BittrService()
    private let baseURL = URL(string: "https://staging.getbittr.com/api/")!
    private let session = URLSession(configuration: .default)
    
    func payoutLightning(notificationId: String, invoice: String, signature: String, pubkey: String) async throws -> BittrPayoutResponse {
            
        var urlComponents = URLComponents(string: "https://staging.getbittr.com/api/payout/lightning")!
        urlComponents.queryItems = [
            URLQueryItem(name: "notification_id", value: notificationId),
            URLQueryItem(name: "invoice", value: invoice),
            URLQueryItem(name: "signature", value: signature),
            URLQueryItem(name: "pubkey", value: pubkey)
        ]
        
        guard let url = urlComponents.url else {
            throw BittrServiceError.other("Invalid URL" as! Error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw BittrServiceError.serverError("Invalid server response")
        }
        
        let decodedResponse = try JSONDecoder().decode(BittrPayoutResponse.self, from: data)
        
        if decodedResponse.success {
            if let preImage = decodedResponse.preImage {
                return decodedResponse
            } else {
                throw BittrServiceError.noData
            }
        } else {
            throw BittrServiceError.serverError(decodedResponse.error ?? "Unknown error")
        }
    }
    
    func fetchBittrTransactions(txIds: [String], depositCodes: [String]) async throws -> [BittrTransaction] {
        
        let txIdsString = txIds.joined(separator: ",")
        let depositCodesString = depositCodes.joined(separator: ",")
        let messageString =  depositCodesString + txIdsString
        
        print(messageString)
        
        let lightningSignature: String
        
        do {
            lightningSignature = try await LightningNodeService.shared.signMessage(message: messageString)
            print("Fetched signature: " + lightningSignature)
        } catch {
            throw BittrServiceError.networkError(error)
        }
        
        let lightningPubKey = LightningNodeService.shared.nodeId()
        
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent("transaction_info"), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [
            URLQueryItem(name: "tx_ids", value: txIdsString),
            URLQueryItem(name: "deposit_codes", value: depositCodesString),
            URLQueryItem(name: "signature", value: lightningSignature),
            URLQueryItem(name: "pubkey", value: lightningPubKey)
        ]
        
        guard let url = urlComponents.url else {
            throw BittrServiceError.other("Invalid URL" as! Error)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw BittrServiceError.serverError("Invalid server response")
        }
        
        let decodedResponse = try JSONDecoder().decode(BittrTransactionResponse.self, from: data)
        
        if decodedResponse.success {
            if let data = decodedResponse.data {
                return data
            } else {
                throw BittrServiceError.noData
            }
        } else {
            throw BittrServiceError.serverError(decodedResponse.error ?? "Unknown error")
        }
    }
    
}

struct BittrPayoutResponse: Codable {
    let success: Bool
    let error: String?
    let preImage: String?
    let bitcoinAmount: String?
    let fiatAmount: String?
    let fiatCurrency: String?

    enum CodingKeys: String, CodingKey {
        case success
        case error
        case preImage = "pre_image"
        case bitcoinAmount = "bitcoin_amount"
        case fiatAmount = "fiat_amount"
        case fiatCurrency = "fiat_currency"
    }
}

struct BittrTransactionResponse: Codable {
    let success: Bool
    let data: [BittrTransaction]?
    let error: String?
}

struct BittrTransaction: Codable {
    let txId: String
    let transferType: String
    let historicalExchangeRate: String
    let datetime: String
    let currency: String
    let purchaseAmount: String

    enum CodingKeys: String, CodingKey {
        case txId = "tx_id"
        case transferType = "transfer_type"
        case historicalExchangeRate = "historical_exchange_rate"
        case datetime
        case currency
        case purchaseAmount = "purchase_amount"
    }
}

enum BittrServiceError: Error {
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)
    case other(Error)
    case noData
}

extension BittrServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return message
        case .networkError(let error):
            return error.localizedDescription
        case .decodingError(_):
            return "Failed to decode the server response."
        case .noData:
            return "No data received from the server."
        case .other(let error):
            return error.localizedDescription
        }
    }
}


