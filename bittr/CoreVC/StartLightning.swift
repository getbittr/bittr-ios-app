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
        self.startSync(type: "ldk")
        
        let startTask = Task {
            let taskResult = try await LightningNodeService.shared.start()
            //print("Reached a result.")
            try Task.checkCancellation()
            //if !Task.isCancelled {
                return taskResult
            //}
        }
        
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
            startTask.cancel()
            print("Could not start node within 10 seconds.")
            //DispatchQueue.main.async {
            self.stopLightning(notification: nil, stopNode: true)
        }
        
        Task.init {
            do {
                let result = try await startTask.value
                timeoutTask.cancel()
                print("Did start node.")
                self.completeSync(type: "ldk")
                self.startSync(type: "bdk")
                DispatchQueue.global(qos: .background).async {
                    LightningNodeService.shared.startBDK()
                }
                self.didStartNode = true
                /*DispatchQueue.main.async {
                    LightningNodeService.shared.startBDK()
                }*/
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                print("Can't start node. \(errorString.title): \(errorString.detail)")
                timeoutTask.cancel()
                if errorString.title == "AlreadyRunning" {
                    self.completeSync(type: "ldk")
                    if self.didStartNode == false {
                        DispatchQueue.global(qos: .background).async {
                            LightningNodeService.shared.startBDK()
                        }
                        self.didStartNode = true
                    }
                } else {
                    self.stopLightning(notification: nil, stopNode: false)
                }
            } catch {
                print("Can't start node. \(error.localizedDescription)")
                timeoutTask.cancel()
                self.stopLightning(notification: nil, stopNode: false)
            }
        }
    }
    
    @objc func stopLightning(notification:NSNotification?, stopNode:Bool) {
        
        //DispatchQueue.main.async {
            if let actualNotification = notification {
                
                do {
                    //DispatchQueue.global(qos: .background).async {
                        try LightningNodeService.shared.stop()
                        print("Node stopped.")
                    //}
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
                        DispatchQueue.main.async {
                            self.present(alert, animated: true)
                        }
                    }
                }
            } else {
                let alert = UIAlertController(title: "Oops!", message: "We can't connect to your wallet. Please try again or check your connection.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Try again", style: .cancel, handler: {_ in
                    do {
                        //DispatchQueue.global(qos: .background).async {
                        if stopNode == true {
                            //try LightningNodeService.shared.stop()
                            //print("Node stopped.")
                            self.startLightning()
                        } else {
                            self.startLightning()
                        }
                    } catch let error as NodeError {
                        let errorString = handleNodeError(error)
                        print("Can't stop node. \(errorString.title): \(errorString.detail)")
                        if errorString.title == "NotRunning" {
                            self.startLightning()
                        }
                    } catch {
                        print("Can't stop node. \(error.localizedDescription)")
                        self.startLightning()
                    }
                }))
                self.present(alert, animated: true)
            }
        //}
    }

}
