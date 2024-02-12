//
//  StartLightning.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import LDKNode

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
            try await Task.sleep(nanoseconds: UInt64(5) * NSEC_PER_SEC)
            startTask.cancel()
            print("Row 141 taking too long.")
            DispatchQueue.main.async {
                do {
                    try LightningNodeService.shared.stop()
                    print("Node stopped.")
                } catch let error as NodeError {
                    let errorString = handleNodeError(error)
                    print("Can't stop node. \(errorString.title): \(errorString.detail)")
                } catch {
                    print("Can't stop node. \(error.localizedDescription)")
                }
                let alert = UIAlertController(title: "Oops!", message: "We can't connect to your wallet. Please try again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Try again", style: .cancel, handler: {_ in
                    self.startLightning()
                }))
                self.present(alert, animated: true)
            }
        }
        
        Task.init {
            do {
                let result = try await startTask.value
                timeoutTask.cancel()
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
        }
    }

}
