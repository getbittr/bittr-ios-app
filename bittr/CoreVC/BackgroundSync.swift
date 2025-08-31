//
//  BackgroundSync.swift
//  bittr
//
//  Created by Tom Melters on 8/27/25.
//

import Foundation

class BackgroundSync {
    
    private var timer: DispatchSourceTimer?
    
    func start() {
        let queue = DispatchQueue(label: "com.myapp.backgroundSync")
        self.timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer?.schedule(deadline: .now() + 30, repeating: 30.0)
        self.timer?.setEventHandler { [weak self] in
            self?.lightSync()
        }
        self.timer?.resume()
    }
    
    func lightSync() {
        LightningNodeService.shared.lightSync() { _ in }
    }
    
    func stop() {
        self.timer?.cancel()
        self.timer = nil
    }
}
