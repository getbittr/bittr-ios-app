//
//  SwapLiveActivityController.swift
//  bittr
//
//  App-side control of the onchain→lightning swap Live Activity (Dynamic Island
//  / Lock Screen): started when the swap begins, updated as the app learns new
//  Boltz statuses, ended (with a lingering "done" state) on completion. The
//  shared attributes live in SwapActivityAttributes.swift, which is compiled
//  into both the app and the widget extension.
//
//  Phase 1: local updates only. The elapsed timer renders on-device, so it keeps
//  ticking while the app is suspended; phase changes still need the app (or,
//  later, an ActivityKit push) to deliver them.
//

import Foundation
import ActivityKit

enum SwapLiveActivityController {

    // Start (or restart) the activity for a swap. Safe to call once per swap.
    @discardableResult
    static func start(swap: Swap) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Log.info("Live Activities are not enabled by the user.")
            return false
        }
        guard let boltzID = swap.boltzID else { return false }

        // Don't stack duplicates if one is already live for this swap.
        guard !isLive(boltzID: boltzID) else { return true }

        let attributes = SwapActivityAttributes(
            swapID: boltzID,
            directionIsOnchainToLightning: swap.swapDirection == .onchainToLightning,
            targetSats: swap.satoshisAmount,
            expectedOnchainSats: swap.boltzExpectedAmount ?? 0
        )
        let state = SwapActivityAttributes.ContentState(
            phase: .preparing,
            statusLine: Language.getWord(withID: "swapstatuspreparing"),
            startedAt: Date()
        )

        do {
            _ = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
            Log.info("Started swap Live Activity for \(boltzID).")
            return true
        } catch {
            Log.info("Failed to start swap Live Activity: \(error)")
            return false
        }
    }

    // Update — or, on a terminal status, finish — the activity from a Boltz status.
    static func update(boltzID: String, boltzStatus: String, statusLine: String) {
        let phase = SwapPhase.from(boltzStatus: boltzStatus)
        Task {
            for activity in activities(for: boltzID) {
                let newState = SwapActivityAttributes.ContentState(
                    phase: phase,
                    statusLine: statusLine,
                    startedAt: activity.content.state.startedAt   // preserve the timer origin
                )

                guard phase.isTerminal else {
                    await activity.update(.init(state: newState, staleDate: nil))
                    continue
                }

                // Announce the finish — a little island pop + haptic — then let the
                // final state linger visibly before ending (an ended activity leaves
                // the Dynamic Island almost immediately).
                await activity.update(.init(state: newState, staleDate: nil),
                                      alertConfiguration: completionAlert(for: phase))
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await activity.end(.init(state: newState, staleDate: nil), dismissalPolicy: .after(.now + 60))
            }
        }
    }

    // Force-end any live swap activities (e.g. on manual cancel).
    static func endAll() {
        Task {
            for activity in Activity<SwapActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Helpers

    private static func activities(for boltzID: String) -> [Activity<SwapActivityAttributes>] {
        Activity<SwapActivityAttributes>.activities.filter { $0.attributes.swapID == boltzID }
    }

    private static func isLive(boltzID: String) -> Bool {
        !activities(for: boltzID).isEmpty
    }

    private static func completionAlert(for phase: SwapPhase) -> AlertConfiguration {
        phase == .complete
            ? AlertConfiguration(title: "Swap complete", body: "Your lightning balance is ready ⚡️", sound: .default)
            : AlertConfiguration(title: "Swap failed", body: "Tap to see what happened.", sound: .default)
    }
}
