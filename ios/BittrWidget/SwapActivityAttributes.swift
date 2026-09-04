//
//  SwapActivityAttributes.swift
//  bittr + BittrWidget (shared)
//
//  The Live Activity attributes for an onchain→lightning swap. This file is
//  compiled into BOTH the app target (which starts/updates/ends the activity)
//  and the widget extension (which renders it in the Dynamic Island / Lock
//  Screen). It must therefore stay dependency-free: no app-only types.
//

import Foundation
import ActivityKit

// Coarse phases the island renders, collapsed from Boltz's raw status strings.
// Kept here (shared) so the app and the widget agree on the mapping.
enum SwapPhase: String, Codable, Hashable {
    case preparing
    case waitingConfirmation
    case completing
    case complete
    case failed

    // Map a raw Boltz submarine (onchain→lightning) status to a phase.
    static func from(boltzStatus: String) -> SwapPhase {
        switch boltzStatus {
        case "swap.created", "invoice.set":
            return .preparing
        case "transaction.mempool":
            return .waitingConfirmation
        case "transaction.confirmed", "invoice.pending":
            return .completing
        case "invoice.paid", "transaction.claim.pending", "transaction.claimed", "invoice.settled":
            return .complete
        case "invoice.failedToPay", "swap.expired", "transaction.lockupFailed",
             "invoice.expired", "transaction.failed", "transaction.refunded":
            return .failed
        default:
            return .preparing
        }
    }

    var isTerminal: Bool { self == .complete || self == .failed }
}

struct SwapActivityAttributes: ActivityAttributes {

    // Dynamic state — updated as the swap progresses. Kept minimal and
    // primitive so a remote Live Activity push only has to send these two
    // fields, and so there's no ambiguity in the pushed JSON:
    //  - boltzStatus: the raw Boltz status; the widget derives the phase and all
    //    labels from it (single source of truth via SwapPhase.from), so the
    //    backend never has to replicate the mapping.
    //  - startedAt: Unix epoch seconds (a plain number). ActivityKit decodes a
    //    Date in content-state as seconds-since-2001, which is a classic footgun;
    //    a Double sidesteps it.
    public struct ContentState: Codable, Hashable {
        var boltzStatus: String
        var startedAt: Double

        var phase: SwapPhase { SwapPhase.from(boltzStatus: boltzStatus) }
        var startDate: Date { Date(timeIntervalSince1970: startedAt) }
    }

    // Static attributes — fixed for the life of the activity.
    var swapID: String                        // Boltz swap id (activity key)
    var directionIsOnchainToLightning: Bool
    var targetSats: Int                       // lightning amount the user receives
    var expectedOnchainSats: Int              // sats sent on-chain to Boltz
}
