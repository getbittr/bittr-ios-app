//
//  SwapLiveActivity.swift
//  BittrWidget
//
//  Renders the onchain→lightning swap Live Activity in the Dynamic Island and
//  on the Lock Screen. State is delivered by the app via ActivityKit.
//

import ActivityKit
import WidgetKit
import SwiftUI

// bittr yellow accent.
private let bittrYellow = Color(red: 0.98, green: 0.79, blue: 0.14)

// A generous visual estimate for the on-chain confirmation wait. The animated
// bar fills across this window; it's decorative (the real signal is the phase),
// so we keep it long enough that it rarely tops out before confirmation.
private let estimatedConfirmationWindow: TimeInterval = 15 * 60

// Tapping the activity opens the app here; the app routes it to the swap status.
private let swapDeepLink = URL(string: "bittr://swapstatus")

// MARK: - Phase presentation helpers

private extension SwapPhase {
    var title: String {
        switch self {
        case .preparing:           return "Preparing swap"
        case .waitingConfirmation: return "Waiting for confirmation"
        case .completing:          return "Finishing up"
        case .complete:            return "Swap complete"
        case .failed:              return "Swap failed"
        }
    }

    var subtitle: String {
        switch self {
        case .preparing:           return "Setting things up"
        case .waitingConfirmation: return "Your bitcoin is being mined into a block"
        case .completing:          return "Paying your lightning invoice"
        case .complete:            return "Your lightning balance is ready ⚡️"
        case .failed:              return "Tap to see what happened"
        }
    }

    var systemIcon: String {
        switch self {
        case .preparing:           return "hourglass"
        case .waitingConfirmation: return "shippingbox.fill"     // "mining into a block"
        case .completing:          return "bolt.horizontal.fill"
        case .complete:            return "checkmark.circle.fill"
        case .failed:              return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .complete: return .green
        case .failed:   return .red
        default:        return bittrYellow
        }
    }

    var showsTimer: Bool { self == .waitingConfirmation || self == .completing }
}

// MARK: - Small building blocks

// The animated "mining" bar (fills over the estimated window) or a filled/idle
// bar for terminal states.
private struct SwapProgressBar: View {
    let state: SwapActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .waitingConfirmation, .completing:
            ProgressView(
                timerInterval: state.startedAt...state.startedAt.addingTimeInterval(estimatedConfirmationWindow),
                countsDown: false
            ) { EmptyView() } currentValueLabel: { EmptyView() }
            .progressViewStyle(.linear)
            .tint(bittrYellow)
        case .complete:
            ProgressView(value: 1).progressViewStyle(.linear).tint(.green)
        case .failed:
            ProgressView(value: 1).progressViewStyle(.linear).tint(.red)
        case .preparing:
            ProgressView(value: 0.12).progressViewStyle(.linear).tint(bittrYellow)
        }
    }
}

private struct TimerOrIcon: View {
    let state: SwapActivityAttributes.ContentState
    var compact = false

    var body: some View {
        if state.phase.showsTimer {
            Text(state.startedAt, style: .timer)
                .font(compact ? .body : .title3).monospacedDigit().fontWeight(.semibold)
                .foregroundStyle(bittrYellow)
                .frame(maxWidth: compact ? 52 : 74, alignment: .trailing)
        } else {
            Image(systemName: state.phase.systemIcon)
                .font(compact ? .body : .title)
                .foregroundStyle(state.phase.tint)
        }
    }
}

// MARK: - Lock Screen / banner

struct SwapLockScreenView: View {
    let context: ActivityViewContext<SwapActivityAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill").font(.title3).foregroundStyle(bittrYellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("bittr swap").font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                    Text(state.phase.title).font(.headline).foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                if state.phase.showsTimer {
                    VStack(alignment: .trailing, spacing: 1) {
                        TimerOrIcon(state: state)
                        Text("elapsed").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: state.phase.systemIcon).font(.title).foregroundStyle(state.phase.tint)
                }
            }

            SwapProgressBar(state: state)

            HStack {
                Text(state.phase.subtitle).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text("\(context.attributes.targetSats.formatted()) sats → lightning")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Live Activity + Dynamic Island

struct SwapLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SwapActivityAttributes.self) { context in
            SwapLockScreenView(context: context)
                .padding(14)
                .widgetURL(swapDeepLink)
                // No forced black tint — use the system's adaptive material so
                // it stays readable in both light and dark.

        } dynamicIsland: { context in
            let state = context.state

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("bittr swap").font(.caption).fontWeight(.semibold)
                    } icon: {
                        Image(systemName: "bolt.fill").foregroundStyle(bittrYellow)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.phase.showsTimer {
                        Text(state.startedAt, style: .timer)
                            .monospacedDigit().fontWeight(.semibold)
                            .foregroundStyle(bittrYellow)
                            .frame(maxWidth: 60, alignment: .trailing)
                    } else {
                        Image(systemName: state.phase.systemIcon).foregroundStyle(state.phase.tint)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.phase.title).font(.headline)
                        SwapProgressBar(state: state)
                        Text("\(context.attributes.targetSats.formatted()) sats → lightning")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                    .widgetURL(swapDeepLink)
                }
            } compactLeading: {
                Image(systemName: "bolt.fill").foregroundStyle(bittrYellow)
                    .widgetURL(swapDeepLink)
            } compactTrailing: {
                TimerOrIcon(state: state, compact: true)
                    .widgetURL(swapDeepLink)
            } minimal: {
                Image(systemName: state.phase.showsTimer ? "bolt.fill" : state.phase.systemIcon)
                    .foregroundStyle(state.phase.tint)
                    .widgetURL(swapDeepLink)
            }
            .keylineTint(bittrYellow)
        }
    }
}
