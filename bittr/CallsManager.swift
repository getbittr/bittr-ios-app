//
//  CallsManager.swift
//  bittr
//
//  Created by Tom Melters on 23/04/2025.
//

import UIKit
import LDKNode

enum APIError: Error {
    case invalidURL
    case requestFailed(String)
    case decodingFailed
}

class CallsManager: NSObject {
    
    static func makeApiCall(url:String, parameters:[String:Any]?, getOrPost:String, completion: @escaping (Result<NSDictionary, APIError>) -> Void) async {
        
        var request = URLRequest(url: URL(string: url.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!,timeoutInterval: Double.infinity)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = getOrPost
        
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
                
                print("Data received: \(String(data:data, encoding:.utf8)!)")
                
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
                        completion(.failure(.decodingFailed))
                        return
                    }
                } else {
                    completion(.failure(.decodingFailed))
                    return
                }
            }
            task.resume()
        } catch let error as NodeError {
            completion(.failure(.requestFailed("\(handleNodeError(error))")))
        } catch {
            completion(.failure(.requestFailed(error.localizedDescription)))
        }
    }
}
