//
//  WebSocketManager.swift
//  bittr
//
//  Created by Tom Melters on 17/02/2025.
//

import UIKit
import Foundation

class WebSocketManager: NSObject, URLSessionWebSocketDelegate {

    var delegate: Any?
    var swapID:String?
    var webSocketTask: URLSessionWebSocketTask?
    var url = URL(string: "wss://api.boltz.exchange/v2/ws")!
    var session: URLSession?
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        
    override init() {
        super.init()
        // Create a URLSession with a background configuration
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        // Listen for app entering background/foreground
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    @objc func appWillEnterForeground() {
        print("App entered foreground, reconnecting WebSocket...")
        connect()
    }

    @objc func appDidEnterBackground() {
        print("App entered background, disconnecting WebSocket...")
        disconnect()
    }
    
    func connect() {
        
        guard let session = session else {
            print("Session is not initialized")
            return
        }
        // Start background task
        startBackgroundTask()
        
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            url = URL(string: "wss://api.regtest.getbittr.com/v2/ws")!
        }
        // Establish WebSocket connection
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        receiveMessage() // Start receiving messages
    }
    
    func sendMessage(_ message: String) {
        
        guard let swapID = self.swapID else {
            print("No SwapID has been set.")
            return
        }
        
        let messageDict: [String: Any] = [
            "op": "subscribe",
            "channel": "swap.update",
            "args": [swapID]
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            
            // Create a WebSocket message from the JSON data
            let webSocketMessage = URLSessionWebSocketTask.Message.data(jsonData)
            
            // Send the message
            webSocketTask?.send(webSocketMessage) { error in
                if let error = error {
                    print("Failed to send message: \(error)")
                } else {
                    print("Message sent: \(messageDict)")
                }
            }
        } catch {
            print("Failed to serialize message to JSON: \(error)")
        }
    }
    
    func receiveMessage() {
        
        guard let delegate = self.delegate as? SwapViewController else {
            print("No delegate set for received message.")
            return
        }
        
        webSocketTask?.receive { result in
            switch result {
            case .failure(let error):
                print("Failed to receive message: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    print("Received string: \(text)")
                case .data(let data):
                    print("Received data: \(data)")
                    
                    var dataDictionary:NSDictionary?
                    print("97 Received data: \(String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) ?? data)")
                    if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                        do {
                            dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                            if let actualDataDict = dataDictionary {
                                if let receivedArguments = actualDataDict["args"] as? NSDictionary, let receivedStatus = receivedArguments["status"] as? String {
                                    
                                    print("Received status: \(receivedStatus)")
                                    delegate.receivedStatusUpdate(status: receivedStatus)
                                } else {
                                    print("107 Status not legible.")
                                }
                            } else {
                                print("110 No dictionary.")
                            }
                        } catch {
                            print("Error 98: \(error.localizedDescription)")
                        }
                    }
                @unknown default:
                    break
                }
            }
            // Continue receiving messages
            self.receiveMessage()
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        endBackgroundTask()
    }
    
    // Background task handling
    func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "WebSocketBackgroundTask") {
            // If time expires, end the background task
            self.endBackgroundTask()
        }
    }
    
    func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // URLSessionWebSocketDelegate methods (optional)
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket connection established")
        sendMessage("subscribe")
        receiveMessage()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWithError error: Error?) {
        if let error = error {
            print("WebSocket closed with error: \(error)")
        } else {
            print("WebSocket closed successfully")
        }
        // Reconnect logic can be placed here if desired
    }
    
}
