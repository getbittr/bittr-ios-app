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

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .requestFailed(let message):
            return message
        case .decodingFailed:
            return "Could not read the server's response."
        }
    }
}

class CallsManager: NSObject {
    
    // How long a request may go without producing data.
    static let defaultTimeout:TimeInterval = 30
    // Ceiling on a whole request, however steadily data trickles in.
    private static let resourceTimeout:TimeInterval = 60
    // Our own session, which never follows a redirect from https to plain http.
    static let session:URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = defaultTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: configuration, delegate: SecureRedirects(), delegateQueue: nil)
    }()
    
    static func makeApiCall(
        url:String,
        parameters:[String:Any]?,
        getOrPost:CallType,
        timeout:TimeInterval = defaultTimeout,
        reportDecodeFailures:Bool = true,
        completion: @escaping (Result<NSDictionary, APIError>) -> Void
    ) async {
        
        var request = URLRequest(url: URL(string: url.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .controlCharacters))!,timeoutInterval: timeout)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = {
            switch getOrPost {
            case .get: return "GET"
            case .post: return "POST"
            case .patch: return "PATCH"
            }
        }()
        
        // The call being made, for the logs below.
        let endpoint = "\(request.httpMethod ?? "") \(request.url?.host ?? "?")\(request.url?.path ?? "")"
        
        do {
            if parameters != nil {
                let postData = try JSONSerialization.data(withJSONObject: parameters!, options: [])
                request.httpBody = postData
            }
            
            let task = Self.session.dataTask(with: request) { data, response, dataError in
                
                if let error = dataError {
                    Log.info("\(endpoint) failed: \(error.localizedDescription)")
                    completion(.failure(.requestFailed(error.localizedDescription)))
                    return
                }
                
                guard let data = data else {
                    Log.info("\(endpoint) returned no data.")
                    completion(.failure(.requestFailed("No data received.")))
                    return
                }
                
                Log.info("Received data from \(endpoint).")
                
                if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                    do {
                        let dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: [.fragmentsAllowed])
                        if let actualDataDict = dataDictionary as? NSDictionary {
                            completion(.success(actualDataDict))
                        } else if let actualInt = dataDictionary as? Int {
                            completion(.success(["result": actualInt] as NSDictionary))
                        } else {
                            completion(.failure(.decodingFailed))
                            return
                        }
                    } catch {
                        if let statusCode = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(statusCode) {
                            Log.info("\(endpoint) failed with status \(statusCode).")
                            completion(.failure(.requestFailed("HTTP \(statusCode)")))
                            return
                        }
                        if reportDecodeFailures {
                            SentryManager.capture(error, context: "CallsManager row 60")
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
            SentryManager.capture(error, context: "CallsManager row 75")
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

// A redirect may not leave https, except to a Tor (.onion) address, which LNURL allows over http.
final class SecureRedirects: NSObject, URLSessionTaskDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let fromScheme = response.url?.scheme?.lowercased()
        let toScheme = request.url?.scheme?.lowercased()
        let toOnion = request.url?.host?.lowercased().hasSuffix(".onion") ?? false
        
        if toScheme == "https" || (toScheme == "http" && (fromScheme == "http" || toOnion)) {
            completionHandler(request)
        } else {
            // Cancelling makes the request fail with an error, rather than finish with the 3xx response's body.
            Log.info("Refused a redirect from \(fromScheme ?? "?") to \(toScheme ?? "?").")
            task.cancel()
            completionHandler(nil)
        }
    }
}

enum CallType {
    case get
    case post
    case patch
}
