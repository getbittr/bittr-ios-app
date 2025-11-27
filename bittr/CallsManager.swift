//
//  CallsManager.swift
//  bittr
//
//  Created by Tom Melters on 23/04/2025.
//

import UIKit
import LDKNode
import Sentry

enum APIError: Error {
    case invalidURL
    case requestFailed(String)
    case decodingFailed
}

class CallsManager: NSObject {
    
    static func makeApiCall(url:String, parameters:[String:Any]?, getOrPost:CallType, completion: @escaping (Result<NSDictionary, APIError>) -> Void) async {
        
        var request = URLRequest(url: URL(string: url.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!,timeoutInterval: Double.infinity)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = {
            switch getOrPost {
            case .get: return "GET"
            case .post: return "POST"
            }
        }()
        
        do {
            if parameters != nil {
                let postData = try JSONSerialization.data(withJSONObject: parameters!, options: [])
                request.httpBody = postData
            }
            
            let task = URLSession.shared.dataTask(with: request) { data, response, dataError in
                
                if let error = dataError {
                    print("Error: \(error.localizedDescription)")
                    completion(.failure(.requestFailed(error.localizedDescription)))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(.requestFailed("No data received.")))
                    return
                }
                
                print("Received data.")
                
                if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                    do {
                        let dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                        if let actualDataDict = dataDictionary {
                            completion(.success(actualDataDict))
                        } else {
                            completion(.failure(.decodingFailed))
                            return
                        }
                    } catch {
                        DispatchQueue.main.async {
                            SentrySDK.capture(error: error) { scope in
                                scope.setExtra(value: "CallsManager row 60", key: "context")
                            }
                        }
                        completion(.failure(.decodingFailed))
                        return
                    }
                } else {
                    completion(.failure(.decodingFailed))
                    return
                }
            }
            task.resume()
        } catch {
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "CallsManager row 75", key: "context")
                }
            }
            let errorMessage:String = {
                if let nodeError = error as? NodeError {
                    return handleNodeError(nodeError).title + ", " + handleNodeError(nodeError).detail
                } else {
                    return error.localizedDescription
                }
            }()
            completion(.failure(.requestFailed(errorMessage)))
        }
    }
}

enum CallType {
    case get
    case post
}
