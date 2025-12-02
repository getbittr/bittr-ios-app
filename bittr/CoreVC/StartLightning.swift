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
                    return await withCheckedContinuation { continuation in
                        LightningNodeService.shared.startLDK { didStartLDK in
                            continuation.resume(returning: didStartLDK)
                        }
                    }
                }
                
                // 15 second timer.
                group.addTask {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(15) * NSEC_PER_SEC)
                    } catch {
                        return false
                    }
                    Log.info("Starting LDK Node takes too long.")
                    return false
                }
                
                // Check connection success.
                let firstResult = await group.next() ?? false
                group.cancelAll()
                return firstResult
            }
            
            // Proceed to next step.
            if self.didStartNode || (LightningNodeService.shared.ldkNode != nil && LightningNodeService.shared.ldkNode!.status().isRunning) {
                Log.info("Did start node.")
                self.didStartNode = true
                self.completeSync(type: .ldk)
                self.startSync(type: .bdk)
                SentrySDK.metrics.increment(key: "sync.ldk.success")
                DispatchQueue.global(qos: .background).async {
                    LightningNodeService.shared.startBDK(coreViewController: self)
                }
            } else {
                Log.info("Could not start node.")
                SentrySDK.metrics.increment(key: "sync.ldk.failure")
                self.stopLightning(message: nil)
            }
        }
    }
    
    @objc func restartLightning() {
        
        self.hideAlert()
        if LightningNodeService.shared.ldkNode != nil, LightningNodeService.shared.ldkNode!.status().isRunning {
            
            // LDK is already running. Start BDK.
            LightningNodeService.shared.startBDK(coreViewController: self)
        } else {
            // LDK isn't running yet.
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
