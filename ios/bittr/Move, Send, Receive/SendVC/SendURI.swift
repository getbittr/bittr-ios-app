//
//  SendURI.swift
//  bittr
//
//  Created by Tom Melters on 2/24/26.
//

import UIKit

extension SendViewController {
    
    func checkForPendingURI() {
        
        if let code = self.pendingPaymentURI {
            self.pendingPaymentURI = nil // Clear after handling
            self.handleScannedOrPastedString(code)
        }
    }
}
