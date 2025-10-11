//
//  StartLightning.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import LDKNode
import LDKNodeFFI
import Sentry

extension CoreViewController {

    func startLightning() {
        
        // Update syncing progress.
        self.startSync(type: .ldk)
        
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
            self.stopLightning(message: nil, stopNode: true)
        }
        
        // Start Bitcoin Dev Kit after successful Lightning node start.
        Task.init {
            do {
                let result = try await startTask.value
                timeoutTask.cancel()
                print("Did start node.")
                self.completeSync(type: .ldk)
                self.startSync(type: .bdk)
                DispatchQueue.global(qos: .background).async {
                    LightningNodeService.shared.startBDK(coreViewController: self)
                }
                self.didStartNode = true
            } catch {
                timeoutTask.cancel()
                if let nodeError = error as? NodeError {
                    let errorString = handleNodeError(nodeError)
                    print("50 Can't start node. \(errorString.title): \(errorString.detail)")
                    if errorString.title == "AlreadyRunning" {
                        self.completeSync(type: .ldk)
                        if !self.didStartNode {
                            self.didStartNode = true
                            DispatchQueue.global(qos: .background).async {
                                LightningNodeService.shared.startBDK(coreViewController: self)
                            }
                        }
                    } else {
                        self.stopLightning(message: nil, stopNode: false)
                    }
                } else {
                    print("63 Can't start node. \(error.localizedDescription)")
                    self.stopLightning(message: nil, stopNode: false)
                }
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "StartLightning row 69", key: "context")
                    }
                }
            }
        }
    }
    
    @objc func restartLightning() {
        
        self.hideAlert()
        if let actualNode = LightningNodeService.shared.ldkNode {
            if actualNode.status().isRunning {
                print("Node is running.")
                LightningNodeService.shared.startBDK(coreViewController: self)
            } else {
                print("Node isn't running. 2")
                self.startLightning()
            }
        } else {
            print("Node isn't running.")
            self.startLightning()
        }
    }
    
    func stopLightning(message:String?, stopNode:Bool) {
        
        if message != nil {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "walletconnectfail")) Error: \(message!)", buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
        } else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail"), buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
        }
    }

}
