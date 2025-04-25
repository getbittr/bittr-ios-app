//
//  CallsManager.swift
//  bittr
//
//  Created by Tom Melters on 23/04/2025.
//

import UIKit
import LDKNode

class CallsManager: NSObject {
    
    static func makeApiCall(url:String, parameters:[String:Any]?, getOrPost:String, completion: @escaping (NSDictionary) -> Void) async {
        
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
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("Status code: \(httpResponse.statusCode)")
                    print("Headers: \(httpResponse.allHeaderFields)")
                }
                
                if let error = dataError {
                    print("Error: \(error.localizedDescription)")
                    let errorDictionary:NSDictionary = ["error":error.localizedDescription]
                    completion(errorDictionary)
                    return
                }
                
                guard let data = data else {
                    let errorDictionary:NSDictionary = ["error":"No data received. Response: \(String(describing: response))."]
                    completion(errorDictionary)
                    return
                }
                
                print("Data received: \(String(data:data, encoding:.utf8)!)")
                
                if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                    do {
                        let dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                        if let actualDataDict = dataDictionary {
                            completion(actualDataDict)
                        } else {
                            let errorDictionary:NSDictionary = ["error":"Received data wasn't in the expected format."]
                            completion(errorDictionary)
                            return
                        }
                    } catch {
                        let errorDictionary:NSDictionary = ["error":error.localizedDescription]
                        completion(errorDictionary)
                    }
                } else {
                    let errorDictionary:NSDictionary = ["error":"Received data wasn't in the expected format."]
                    completion(errorDictionary)
                    return
                }
            }
            task.resume()
        } catch let error as NodeError {
            let errorDictionary:NSDictionary = ["error":"\(handleNodeError(error))"]
            completion(errorDictionary)
        } catch {
            let errorDictionary:NSDictionary = ["error":error.localizedDescription]
            completion(errorDictionary)
        }
    }
}
