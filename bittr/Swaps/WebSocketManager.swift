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
        // Ensure the socket is not already open before reconnecting
        if webSocketTask == nil {
            connect()  // Re-establish connection
        }
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
    
    func sendMessage() {
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
            if let jsonString = String(data: jsonData, encoding: .utf8) {  // Convert Data to String
            let webSocketMessage = URLSessionWebSocketTask.Message.string(jsonString)  // Send as String
                
            webSocketTask?.send(webSocketMessage) { error in
                if let error = error {
                    print("Failed to send message: \(error)")
                } else {
                    print("Message sent: \(jsonString)")  // Log the string version
                }
            }
        } else {
            print("Failed to convert JSON data to String")
        }
        } catch {
            print("Failed to serialize message to JSON: \(error)")
        }
    }

    
    func receiveMessage() {
        guard let webSocketTask = webSocketTask else {
            print("WebSocket task is nil, stopping receiveMessage() to prevent errors.")
            return
        }

        webSocketTask.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("❌ Failed to receive message: \(error.localizedDescription)")
                return

            case .success(let message):
                switch message {
                case .string(let text):
                    print("📩 Received string: \(text)")

                    // Convert JSON string into a Swift dictionary
                    if let data = text.data(using: .utf8) {
                        do {
                            if let jsonDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                                self.handleReceivedMessage(jsonDict)
                            } else {
                                print("❌ Failed to convert JSON into a dictionary.")
                            }
                        } catch {
                            print("❌ JSON Parsing Error: \(error.localizedDescription)")
                        }
                    }

                @unknown default:
                    print("⚠️ Received unknown response format.")
                }
            }

            // Keep listening for new messages
            self.receiveMessage()
        }
    }
    
    func handleReceivedMessage(_ jsonDict: [String: Any]) {
        guard let delegate = self.delegate as? SwapViewController else {
            print("No delegate set for received message.")
            return
        }

        guard let args = jsonDict["args"] as? [[String: Any]], // Expecting an array
              let firstArg = args.first,                      // Get the first item
              let receivedStatus = firstArg["status"] as? String else {
            print("❌ Could not extract status from args.")
            return
        }

        print("✅ Received status: \(receivedStatus)")

        // Ensure status update is performed on the main thread
        DispatchQueue.main.async {
            delegate.receivedStatusUpdate(status: receivedStatus)
        }
    }

    
    func disconnect() {
        // Stop receiving messages (prevents the error spam)
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
            webSocketTask = nil  // Clear the task to prevent reuse of a dead socket
        }
    }
    
    // URLSessionWebSocketDelegate methods (optional)
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket connection established")
        sendMessage()
        receiveMessage()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWithError error: Error?) {
        if let error = error {
            print("WebSocket closed with error: \(error)")
        } else {
            print("WebSocket closed successfully")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.connect()
        }
    }
    
}
