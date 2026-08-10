//
//  Log.swift
//  bittr
//
//  Created by Tom Melters on 12/2/25.
//

import Sentry

struct Log {
    
    static func info(_ message: String) {
        
        DispatchQueue.main.async {
            // Print message.
            print(message)
            
            // Add message to Sentry breadcrumbs.
            let breadcrumb = Breadcrumb()
            breadcrumb.level = .info
            breadcrumb.category = "log"
            breadcrumb.type = "default"
            breadcrumb.message = message.redactSensitiveValues().redactURLs()
            
            SentrySDK.addBreadcrumb(breadcrumb)
        }
    }
}
