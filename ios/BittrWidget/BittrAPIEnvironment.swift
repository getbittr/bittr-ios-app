//
//  BittrAPIEnvironment.swift
//  bittr + BittrWidget (shared)
//
//  The single source of truth for the bittr API base URL.
//
//  This file is compiled into BOTH the app target and the widget extension, so
//  it must stay dependency-free: Foundation only, no LDKNode/BitcoinDevKit, no
//  app-only types. That is why it lives here next to SwapActivityAttributes.swift
//  rather than in bittr/Helpers/ — the widget target is built from the
//  BittrWidget folder as a synchronized group, so anything it needs has to be
//  in this folder. `EnvironmentConfig.bittrAPIBaseURL` forwards to this type,
//  which keeps the app's existing call sites unchanged.
//
//  Anything that talks to the bittr API must build its URL from `baseURL`.
//  Hard-coding "https://getbittr.com/api" makes a debug/regtest build read
//  production — for authenticated endpoints such as /notifications that is a
//  cross-environment read of real customer payout state. The
//  "Check hard-coded API URLs" build phase fails the build if a literal
//  reappears outside this file (see ios/Scripts/check-hardcoded-api-urls.sh).
//

import Foundation

/// Build-environment-dependent bittr API host, shared by the app and the widget.
enum BittrAPIEnvironment {

    /// True for Debug builds (feature work / regtest), false for Release.
    ///
    /// Matches `EnvironmentConfig.currentEnvironment`, which makes the same
    /// DEBUG check. Both targets define DEBUG in their Debug configuration, so
    /// the app and the widget always agree on which backend they are talking to.
    static var isDevelopment: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Base URL for the bittr API, including the `/api` path component.
    /// Append the endpoint path directly, e.g. "\(baseURL)/price/btc".
    static var baseURL: String {
        isDevelopment ? "https://staging.getbittr.com/api" : "https://getbittr.com/api"
    }
}
