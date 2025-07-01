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

// MARK: - BoltzAPIError

enum BoltzAPIError: Error {
    case invalidURL
    case requestFailed(String)
    case decodingFailed
}

// MARK: - BoltzAPI Class

class BoltzAPI {
    static let baseURL = "https://api.regtest.getbittr.com/v2/swap/submarine/"
    static let reverseBaseURL = "https://api.regtest.getbittr.com/v2/swap/reverse/"
    
    // Generic POST request method
    static func post<T: Codable, U: Codable>(endpoint: String, body: T, completion: @escaping (Result<U, BoltzAPIError>) -> Void) {
        guard let url = URL(string: baseURL + endpoint) else {
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
        guard let url = URL(string: reverseBaseURL + endpoint) else {
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
}
