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
        
        // Start Lightning node.
        let startTask = Task {
            let taskResult = try await LightningNodeService.shared.start()
            try Task.checkCancellation()
            return taskResult
        }
        
        // Time out Lightning node start after 10 seconds.
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
            startTask.cancel()
            print("Could not start node within 10 seconds.")
            self.stopLightning(notification: nil, stopNode: true)
        }
        
        // Start Bitcoin Dev Kit after successful Lightning node start.
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
        
        if let actualNotification = notification {
            
            /*do {
                try LightningNodeService.shared.stop()
                print("Node stopped.")
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                print("Can't stop node. \(errorString.title): \(errorString.detail)")
            } catch {
                print("Can't stop node. \(error.localizedDescription)")
            }*/
            
            if let userInfo = actualNotification.userInfo as [AnyHashable:Any]? {
                if let notificationMessage = userInfo["message"] as? String {
                    let alert = UIAlertController(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "walletconnectfail")) Error: \(notificationMessage)", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Language.getWord(withID: "tryagain"), style: .cancel, handler: {_ in
                        if let actualNode = LightningNodeService.shared.ldkNode {
                            if actualNode.status().isRunning {
                                print("Node is running.")
                                LightningNodeService.shared.startBDK()
                            } else {
                                print("Node isn't running. 2")
                                self.startLightning()
                            }
                        } else {
                            print("Node isn't running.")
                            self.startLightning()
                        }
                    }))
                    DispatchQueue.main.async {
                        self.present(alert, animated: true)
                    }
                }
            }
        } else {
            let alert = UIAlertController(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "tryagain"), style: .cancel, handler: {_ in
                do {
                    self.startLightning()
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
    }

}
