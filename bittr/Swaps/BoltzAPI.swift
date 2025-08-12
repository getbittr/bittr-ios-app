//
//  BoltzAPI.swift
//  bittr
//
//  Created by Ruben Waterman on 19/03/2025.
//
import Foundation

// MARK: - Refund Models

struct RefundRequest: Codable {
    let pubNonce: String
    let transaction: String
    let index: Int
}

struct RefundResponse: Codable {
    let pubNonce: String?
    let partialSignature: String?
    let error: String?
}

// MARK: - Claim Models

struct ClaimRequest: Codable {
    let index: Int
    let transaction: String
    let preimage: String
    let pubNonce: String
}

struct ClaimResponse: Codable {
    let pubNonce: String?
    let partialSignature: String?
    let error: String?
}

// MARK: - Broadcast Models

struct BroadcastRequest: Codable {
    let hex: String
}

struct BroadcastResponse: Codable {
    let transactionId: String?
    let txid: String?
    let id: String?
    let error: String?
    
    // Computed property to get the transaction ID from any field
    var transactionIdValue: String? {
        return transactionId ?? txid ?? id
    }
}

// MARK: - BoltzAPIError

enum BoltzAPIError: Error {
    case invalidURL
    case requestFailed(String)
    case decodingFailed
}

// MARK: - BoltzAPI Class

class BoltzAPI {
    static var baseURL: String {
        return EnvironmentConfig.boltzBaseURL
    }
    
    // Generic POST request method
    static func post<T: Codable, U: Codable>(endpoint: String, body: T, completion: @escaping (Result<U, BoltzAPIError>) -> Void) {
        guard let url = URL(string: baseURL + "/swap/submarine/" + endpoint) else {
            completion(.failure(.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(.decodingFailed))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.requestFailed(error.localizedDescription)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.requestFailed("No data received")))
                return
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(U.self, from: data)
                completion(.success(decodedResponse))
            } catch {
                completion(.failure(.decodingFailed))
            }
        }
        
        task.resume()
    }
    
    // Generic POST request method for reverse swaps
    static func postReverse<T: Codable, U: Codable>(endpoint: String, body: T, completion: @escaping (Result<U, BoltzAPIError>) -> Void) {
        guard let url = URL(string: baseURL + "/swap/reverse/" + endpoint) else {
            completion(.failure(.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(.decodingFailed))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.requestFailed(error.localizedDescription)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.requestFailed("No data received")))
                return
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(U.self, from: data)
                completion(.success(decodedResponse))
            } catch {
                completion(.failure(.decodingFailed))
            }
        }
        
        task.resume()
    }
    
    // Refund specific API method
    static func requestRefund(swapID: String, refundData: RefundRequest, completion: @escaping (Result<RefundResponse, BoltzAPIError>) -> Void) {
        post(endpoint: "\(swapID)/refund", body: refundData, completion: completion)
    }
    
    // Claim specific API method
    static func requestClaim(swapID: String, claimData: ClaimRequest, completion: @escaping (Result<ClaimResponse, BoltzAPIError>) -> Void) {
        postReverse(endpoint: "\(swapID)/claim", body: claimData, completion: completion)
    }
    
    // Broadcast transaction method
    static func broadcastTransaction(transactionHex: String, completion: @escaping (Result<BroadcastResponse, BoltzAPIError>) -> Void) {
        guard let url = URL(string: "\(baseURL)/chain/BTC/transaction") else {
            completion(.failure(.invalidURL))
            return
        }
        
        print("🔍 Broadcasting transaction: \(transactionHex)")
        let broadcastRequest = BroadcastRequest(hex: transactionHex)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            request.httpBody = try JSONEncoder().encode(broadcastRequest)
        } catch {
            completion(.failure(.decodingFailed))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.requestFailed(error.localizedDescription)))
                return
            }
            
            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Broadcast API Status Code: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 && httpResponse.statusCode != 201 {
                    // For error responses, try to get the error message from the response body
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("🔍 Error Response Body: \(errorString)")
                        completion(.failure(.requestFailed("HTTP \(httpResponse.statusCode): \(errorString)")))
                    } else {
                        completion(.failure(.requestFailed("HTTP \(httpResponse.statusCode)")))
                    }
                    return
                }
            }
            
            guard let data = data else {
                completion(.failure(.requestFailed("No data received")))
                return
            }
            
            // Debug: Print the raw response
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔍 Broadcast API Response: \(responseString)")
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(BroadcastResponse.self, from: data)
                completion(.success(decodedResponse))
            } catch {
                print("❌ Failed to decode broadcast response: \(error)")
                // Try to decode as a simple string response
                if let responseString = String(data: data, encoding: .utf8) {
                    // If it's just a transaction ID string, create a response
                    let simpleResponse = BroadcastResponse(transactionId: responseString, txid: nil, id: nil, error: nil)
                    completion(.success(simpleResponse))
                } else {
                    completion(.failure(.decodingFailed))
                }
            }
        }
        
        task.resume()
    }
    
    // Async version of broadcast transaction
    static func broadcastTransaction(transactionHex: String) async throws -> BroadcastResponse {
        return try await withCheckedThrowingContinuation { continuation in
            broadcastTransaction(transactionHex: transactionHex) { result in
                switch result {
                case .success(let response):
                    continuation.resume(returning: response)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
