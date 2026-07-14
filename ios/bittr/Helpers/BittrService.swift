//
//  BittrService.swift
//  bittr
//
//  Created by Tom Melters on 07/11/2023.
//

import Foundation
import Sentry

class BittrService {

    static let shared = BittrService()
    private let session = URLSession(configuration: .default)
    
    func payoutLightning(notificationId: String, invoice: String, signature: String, pubkey: String) async throws -> BittrPayoutResponse {
        let envUrl = "\(EnvironmentConfig.bittrAPIBaseURL)/payout/lightning"
        
        var urlComponents = URLComponents(string: envUrl)!
        urlComponents.queryItems = [
            URLQueryItem(name: "notification_id", value: notificationId),
            URLQueryItem(name: "invoice", value: invoice),
            URLQueryItem(name: "signature", value: signature),
            URLQueryItem(name: "pubkey", value: pubkey)
        ]
        
        guard let url = urlComponents.url else {
            throw BittrServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw BittrServiceError.serverError("Couldn't connect to Bittr to complete payout. Please try again or check your connection.")
        }
        
        let decodedResponse = try JSONDecoder().decode(BittrPayoutResponse.self, from: data)
        
        if decodedResponse.success {
            if let preImage = decodedResponse.preImage {
                return decodedResponse
            } else {
                throw BittrServiceError.noData
            }
        } else {
            // Check for specific error codes that require special handling
            if let errorCode = decodedResponse.errorCode, 
               errorCode == "CHANNEL_FULL",
               let suggestedAmount = decodedResponse.suggestedSwapAmount {
                throw BittrServiceError.channelFullWithSwapSuggestion(
                    decodedResponse.error ?? "Lightning channel capacity insufficient",
                    suggestedAmount
                )
            } else {
                throw BittrServiceError.serverError(decodedResponse.error ?? "Unknown error")
            }
        }
    }
    
    func fetchBittrTransactions(txIds: [String], depositCodes: [String]) async throws -> [BittrTransaction] {
        
        let txIdsString = txIds.joined(separator: ",")
        let depositCodesString = depositCodes.joined(separator: ",")
        let messageString =  depositCodesString + txIdsString
        
        let lightningSignature: String
        
        var lightningPubKey = String()
        if let pubkeyString = BitcoinManager.shared.nodeId() {
            lightningPubKey = pubkeyString
        } else {
            Log.info("Wallet has not yet synced. Cannot fetch pubkey.")
            throw BittrServiceError.unsyncedWallet
        }
        
        do {
            lightningSignature = try await BitcoinManager.shared.signMessage(message: messageString)
            Log.info("Did fetch Lightning signature.")
            
            let envUrl = URL(string: EnvironmentConfig.bittrAPIBaseURL)!
            
            var urlComponents = URLComponents(url: envUrl.appendingPathComponent("/transaction_info"), resolvingAgainstBaseURL: false)!
            urlComponents.queryItems = [
                URLQueryItem(name: "tx_ids", value: txIdsString),
                URLQueryItem(name: "deposit_codes", value: depositCodesString),
                URLQueryItem(name: "signature", value: lightningSignature),
                URLQueryItem(name: "pubkey", value: lightningPubKey)
            ]
            
            guard let url = urlComponents.url else {
                throw BittrServiceError.invalidURL
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
        } catch {
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "BittrService row 114", key: "context")
                }
            }
            throw BittrServiceError.networkError(error)
        }
    }
    
    func markTransactionAsOnchain(notificationId: String, signature: String, pubkey: String) async throws -> BittrPayoutResponse {
        let envUrl = "\(EnvironmentConfig.bittrAPIBaseURL)/payout/onchain"
        
        var urlComponents = URLComponents(string: envUrl)!
        urlComponents.queryItems = [
            URLQueryItem(name: "notification_id", value: notificationId),
            URLQueryItem(name: "signature", value: signature),
            URLQueryItem(name: "pubkey", value: pubkey)
        ]
        
        guard let url = urlComponents.url else {
            throw BittrServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw BittrServiceError.serverError("Couldn't connect to Bittr to mark transaction as on-chain. Please try again or check your connection.")
        }
        
        let decodedResponse = try JSONDecoder().decode(BittrPayoutResponse.self, from: data)
        
        if decodedResponse.success {
            return decodedResponse
        } else {
            throw BittrServiceError.serverError(decodedResponse.error ?? "Unknown error")
        }
    }
    
    /// Signal that the app is ready to receive an incoming HTLC (call once when wallet is unlocked after HTLC push).
    func htlcReady(depositCode: String, timestamp: Int, pubkey: String, signature: String) async throws -> HtlcReadyResponse {
        let url = URL(string: "\(EnvironmentConfig.bittrAPIBaseURL)/htlc-interceptor/ready")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(HtlcReadyRequest(deposit_code: depositCode, timestamp: timestamp, pubkey: pubkey, signature: signature))
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(HtlcReadyResponse.self, from: data)
        
        guard let http = response as? HTTPURLResponse else {
            throw BittrServiceError.serverError("Invalid response")
        }
        if (200...299).contains(http.statusCode) {
            return decoded
        }
        throw BittrServiceError.serverError(decoded.error ?? "Unknown error")
    }
    
}

struct HtlcReadyRequest: Encodable {
    let deposit_code: String
    let timestamp: Int
    let pubkey: String
    let signature: String
}

struct HtlcReadyResponse: Codable {
    let success: Bool
    let action: String?
    let error: String?
}

struct BittrPayoutResponse: Codable {
    let success: Bool
    let error: String?
    let preImage: String?
    let bitcoinAmount: String?
    let fiatAmount: String?
    let fiatCurrency: String?
    let errorCode: String?
    let suggestedSwapAmount: String?

    enum CodingKeys: String, CodingKey {
        case success
        case error
        case preImage = "pre_image"
        case bitcoinAmount = "bitcoin_amount"
        case fiatAmount = "fiat_amount"
        case fiatCurrency = "fiat_currency"
        case errorCode = "error_code"
        case suggestedSwapAmount = "suggested_swap_amount"
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
    let bitcoinAmount: String
    let transferFee: String // Onchain fees or lightning connection establishment fees.
    let bittrFee: String // 1.5 % of purchase amount after surcharge.
    let surcharge: String // 1€ for purchases under 100€.
    let fiatNetAmount: String
    let fiatGrossAmount: String

    enum CodingKeys: String, CodingKey {
        case txId = "tx_id"
        case transferType = "transfer_type"
        case historicalExchangeRate = "historical_exchange_rate"
        case datetime
        case currency
        case bitcoinAmount = "bitcoin_amount"
        case transferFee = "transfer_fee"
        case bittrFee = "bittr_fee"
        case surcharge
        case fiatNetAmount = "fiat_amount_net"
        case fiatGrossAmount = "fiat_amount_gross"
    }
}

enum BittrServiceError: Error {
    case invalidURL
    case unsyncedWallet
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)
    case other(Error)
    case noData
    case channelFullWithSwapSuggestion(String, String) // error message, suggested amount
}

extension BittrServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Couldn't build a valid request URL."
        case .unsyncedWallet:
            return "Your wallet hasn't finished syncing. Please try again in a moment."
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
        case .channelFullWithSwapSuggestion(let message, let suggestedAmount):
            return "\(message) Suggested swap amount: \(suggestedAmount) sats"
        }
    }
}


