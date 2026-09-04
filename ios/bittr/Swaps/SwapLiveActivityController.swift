//
//  SwapLiveActivityController.swift
//  bittr
//
//  App-side control of the onchain→lightning swap Live Activity (Dynamic Island
//  / Lock Screen): started when the swap begins, updated as the app learns new
//  Boltz statuses, ended (with a lingering "done" state) on completion. The
//  shared attributes live in SwapActivityAttributes.swift, compiled into both
//  the app and the widget extension.
//
//  The activity is requested with a push token so the backend can update it in
//  real time (apns-push-type: liveactivity) while the app is backgrounded — the
//  foreground WebSocket still drives it when the app is open.
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
            boltzStatus: "swap.created",
            startedAt: Date().timeIntervalSince1970
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: .token
            )
            Log.info("Started swap Live Activity for \(boltzID).")
            observePushToken(of: activity, swapID: boltzID)
            return true
        } catch {
            Log.info("Failed to start swap Live Activity: \(error)")
            return false
        }
    }

    // Update — or, on a terminal status, finish — the activity from a Boltz status.
    static func update(boltzID: String, boltzStatus: String) {
        let phase = SwapPhase.from(boltzStatus: boltzStatus)
        Task {
            for activity in activities(for: boltzID) {
                let newState = SwapActivityAttributes.ContentState(
                    boltzStatus: boltzStatus,
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

    // Re-attach push-token observers to any activities that outlived a relaunch,
    // so a rotated token still reaches the backend. Call once at launch.
    static func resumeTokenObservation() {
        for activity in Activity<SwapActivityAttributes>.activities {
            observePushToken(of: activity, swapID: activity.attributes.swapID)
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

    // End any activity that has finished or gone stale. A swap can complete via a
    // push while the app is closed — so the app never runs its own terminal end
    // (that only happens via the foreground socket or a regular push) — leaving
    // the activity stranded. Call on launch / foreground to clean those up.
    static func endStaleActivities() {
        // A swap never legitimately runs this long; past it the activity is dead.
        let maxAge: TimeInterval = 3 * 60 * 60
        Task {
            for activity in Activity<SwapActivityAttributes>.activities {
                let state = activity.content.state
                let isTerminal = SwapPhase.from(boltzStatus: state.boltzStatus).isTerminal
                let isStale = (Date().timeIntervalSince1970 - state.startedAt) > maxAge
                if isTerminal || isStale {
                    await activity.end(activity.content, dismissalPolicy: .immediate)
                }
            }
        }
    }

    // MARK: - Helpers

    // Stream the activity's push token to the backend so it can send
    // liveactivity pushes. The sequence ends when the activity ends.
    private static func observePushToken(of activity: Activity<SwapActivityAttributes>, swapID: String) {
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                Log.info("Swap Live Activity push token for \(swapID): \(hex.prefix(12))…")
                // Send startedAt too: every liveactivity push must carry the full
                // content-state, and only the app knows the activity's start time.
                await SwapManager.registerLiveActivityToken(
                    swapID: swapID,
                    token: hex,
                    startedAt: activity.content.state.startedAt
                )
            }
        }
    }

    private static func activities(for boltzID: String) -> [Activity<SwapActivityAttributes>] {
        Activity<SwapActivityAttributes>.activities.filter { $0.attributes.swapID == boltzID }
    }

    private static func isLive(boltzID: String) -> Bool {
        !activities(for: boltzID).isEmpty
    }

    private static func completionAlert(for phase: SwapPhase) -> AlertConfiguration {
        phase == .complete
            ? AlertConfiguration(title: "Swap complete", body: "Your bitcoin is ready for instant payments ⚡️", sound: .default)
            : AlertConfiguration(title: "Swap didn't go through", body: "Tap to sort it out.", sound: .default)
    }
}
