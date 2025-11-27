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
        
        Task {
            self.didStartNode = await withTaskGroup(of: Bool.self) { group -> Bool in
                
                // Start LDK node.
                group.addTask {
                    do {
                        try await LightningNodeService.shared.start()
                    } catch {
                        print("28 Can't start node. \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            SentrySDK.metrics.increment(key: "sync.ldk.failure")
                            SentrySDK.capture(error: error) { scope in
                                scope.setExtra(value: "StartLightning row 69", key: "context")
                            }
                        }
                        if let nodeError = error as? NodeError {
                            switch nodeError {
                            case .AlreadyRunning(message: _):
                                return true
                            default:
                                return false
                            }
                        } else {
                            return false
                        }
                    }
                    return true
                }
                
                // 15 second timer.
                group.addTask {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(15) * NSEC_PER_SEC)
                    } catch {
                        return false
                    }
                    print("Starting LDK Node takes too long.")
                    return false
                }
                
                // Check connection success.
                let firstResult = await group.next() ?? false
                group.cancelAll()
                return firstResult
            }
            
            // Proceed to next step.
            if self.didStartNode {
                print("Did start node.")
                self.completeSync(type: .ldk)
                self.startSync(type: .bdk)
                SentrySDK.metrics.increment(key: "sync.ldk.success")
                DispatchQueue.global(qos: .background).async {
                    LightningNodeService.shared.startBDK(coreViewController: self)
                }
            } else {
                print("Could not start node.")
                self.stopLightning(message: nil)
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
    
    func stopLightning(message:String?) {
        
        if message != nil {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "walletconnectfail")) Error: \(message!)", buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
        } else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail"), buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
        }
    }

}
