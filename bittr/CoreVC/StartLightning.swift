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

    func startLightning() {
        
        // Update syncing progress.
        self.startSync(type: "ldk")
        
        // Start Lightning node.
        let startTask = Task {
            let taskResult = try await LightningNodeService.shared.start()
            try Task.checkCancellation()
            return taskResult
        }
        
        // Time out Lightning node start after 15 seconds.
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(15) * NSEC_PER_SEC)
            startTask.cancel()
            print("Could not start node within 15 seconds.")
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
                print("48 Can't start node. \(errorString.title): \(errorString.detail)")
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
                print("62 Can't start node. \(error.localizedDescription)")
                timeoutTask.cancel()
                self.stopLightning(notification: nil, stopNode: false)
            }
        }
    }
    
    @objc func restartLightning() {
        
        self.hideAlert()
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
    }
    
    @objc func stopLightning(notification:NSNotification?, stopNode:Bool) {
        
        if let actualNotification = notification {
            if let userInfo = actualNotification.userInfo as [AnyHashable:Any]? {
                if let notificationMessage = userInfo["message"] as? String {
                    self.showAlert(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "walletconnectfail")) Error: \(notificationMessage)", buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
                }
            }
        } else {
            self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail"), buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
        }
    }

}
