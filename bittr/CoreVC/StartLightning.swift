//
//  StartLightning.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import LDKNode
import LDKNodeFFI

extension CoreViewController {

    @objc func startLightning() {
        
        // Step 3.
        
        /*Task {
            do {
                try await LightningNodeService.shared.start()
                print("Started node successfully.")
                DispatchQueue.main.async {
                    LightningNodeService.shared.connectToLightningPeer()
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                print("Can't start node. \(errorString.title): \(errorString.detail)")
            } catch {
                print("Can't start node. \(error.localizedDescription)")
            }
        }*/
        
        let startTask = Task {
            let taskResult = try await LightningNodeService.shared.start()
            try Task.checkCancellation()
            return taskResult
        }
        
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
            startTask.cancel()
            print("Could not start node within 10 seconds. Will stop node.")
            DispatchQueue.main.async {
                self.stopLightning(notification: nil)
                
                do {
                    try LightningNodeService.shared.stop()
                    print("Node stopped.")
                } catch let error as NodeError {
                    let errorString = handleNodeError(error)
                    print("Can't stop node. \(errorString.title): \(errorString.detail)")
                } catch {
                    print("Can't stop node. \(error.localizedDescription)")
                }
            }
        }
        
        Task.init {
            do {
                let result = try await startTask.value
                timeoutTask.cancel()
                print("Did start node.")
                DispatchQueue.main.async {
                    LightningNodeService.shared.startBDK()
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                print("Can't start node. \(errorString.title): \(errorString.detail)")
            } catch {
                print("Can't start node. \(error.localizedDescription)")
            }
        }
    }
    
    @objc func stopLightning(notification:NSNotification?) {
        
        if let actualNotification = notification {
            
            do {
                try LightningNodeService.shared.stop()
                print("Node stopped.")
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                print("Can't stop node. \(errorString.title): \(errorString.detail)")
            } catch {
                print("Can't stop node. \(error.localizedDescription)")
            }
            
            if let userInfo = actualNotification.userInfo as [AnyHashable:Any]? {
                if let notificationMessage = userInfo["message"] as? String {
                    let alert = UIAlertController(title: "Oops!", message: "We can't connect to your wallet. Please try again or check your connection. Error: \(notificationMessage)", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Try again", style: .cancel, handler: {_ in
                        self.startLightning()
                    }))
                    self.present(alert, animated: true)
                }
            }
        } else {
            let alert = UIAlertController(title: "Oops!", message: "We can't connect to your wallet. Please try again or check your connection.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Try again", style: .cancel, handler: {_ in
                self.startLightning()
            }))
            self.present(alert, animated: true)
        }
    }

}
