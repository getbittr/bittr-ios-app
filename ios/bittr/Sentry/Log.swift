//
//  Log.swift
//  bittr
//
//  Created by Tom Melters on 12/2/25.
//

import Sentry

struct Log {
    
    static func info(_ message: String) {
        
        printToConsole(message)
        DispatchQueue.main.async {
            // Add message to Sentry breadcrumbs.
            let breadcrumb = Breadcrumb()
            breadcrumb.level = .info
            breadcrumb.category = "log"
            breadcrumb.type = "default"
            breadcrumb.message = message.redactSensitiveValues().redactURLs()
            
            SentrySDK.addBreadcrumb(breadcrumb)
        }
    }
    
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        printToConsole(message())
        #endif
    }
    
    private static func printToConsole(_ message: String) {
        #if DEBUG
        DispatchQueue.main.async { print(message) }
        #endif
    }
}
