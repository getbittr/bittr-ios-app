//
//  WidgetShare.swift
//  bittr
//
//  Created by Tom Melters on 21/09/2026.
//

import Foundation

// The few values the widget needs from the app. They travel through an app
// group: an extension's own UserDefaults.standard is its container, not the
// app's, so nothing the app writes to the standard suite is visible here.
enum WidgetShare {

    static let appGroup = "group.com.bittr.bittr"

    enum Key {
        static let currency = "currency"
        static let lightningAddress = "lightningaddress"
    }

    static var defaults:UserDefaults? {
        return UserDefaults(suiteName: appGroup)
    }

    // "EUR" or "CHF", matching what the app stores under CacheKeys.currency.
    static var currency:String? {
        return defaults?.string(forKey: Key.currency)
    }

    #if DEBUG
    // Flip this to switch the medium widget between its two layouts without
    // touching wallet data: nil follows the real address, "" forces the chart,
    // anything else forces the QR card. Never reaches a release build.
    static let debugLightningAddress:String? = nil
    #endif

    // The user's lightning address, e.g. someone@staging.getbittr.com. Nil when
    // they haven't signed up with Bittr.
    static var lightningAddress:String? {

        #if DEBUG
        if let override = debugLightningAddress {
            return override.isEmpty ? nil : override
        }
        #endif

        guard let address = defaults?.string(forKey: Key.lightningAddress), !address.isEmpty else { return nil }
        return address
    }

    // Called by the app whenever either value changes.
    static func write(currency:String?, lightningAddress:String?) {

        guard let defaults = self.defaults else { return }

        if let currency = currency {
            defaults.set(currency, forKey: Key.currency)
        } else {
            defaults.removeObject(forKey: Key.currency)
        }

        if let lightningAddress = lightningAddress, !lightningAddress.isEmpty {
            defaults.set(lightningAddress, forKey: Key.lightningAddress)
        } else {
            defaults.removeObject(forKey: Key.lightningAddress)
        }
    }
}
