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


// MARK: - Phase presentation helpers

private extension SwapPhase {
    var title: String {
        switch self {
        case .preparing:           return "Getting ready"
        case .waitingConfirmation: return "Confirming your transfer"
        case .completing:          return "Almost there"
        case .complete:            return "Swap complete"
        case .failed:              return "Swap didn't go through"
        }
    }

    var subtitle: String {
        switch self {
        case .preparing:           return "Setting up your transfer"
        case .waitingConfirmation: return "This usually takes 10–30 minutes"
        case .completing:          return "Adding it to your instant balance"
        case .complete:            return "Your bitcoin is ready for instant payments ⚡️"
        case .failed:              return "Tap to sort it out"
        }
    }

    var systemIcon: String {
        switch self {
        case .preparing:           return "hourglass"
        case .waitingConfirmation: return "clock.fill"
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

    // Where a tap on the activity takes the user. During the final leg (the
    // incoming lightning payment) the wallet must come online to receive it, so
    // route the tap to the resume flow — the same place the HTLC-resume
    // notification goes — rather than just the status screen.
    var deepLink: URL? {
        URL(string: self == .completing ? "bittr://resumeswap" : "bittr://swapstatus")
    }
}

// MARK: - Small building blocks

// The animated progress bar (fills over the estimated confirmation window) or a
// filled/idle bar for terminal states.
private struct SwapProgressBar: View {
    let state: SwapActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .waitingConfirmation, .completing:
            ProgressView(
                timerInterval: state.startDate...state.startDate.addingTimeInterval(estimatedConfirmationWindow),
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
            Text(state.startDate, style: .timer)
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
                Text("\(context.attributes.targetSats.formatted()) sats → instant")
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
                .widgetURL(context.state.phase.deepLink)
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
                        Text(state.startDate, style: .timer)
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
                        Text("\(context.attributes.targetSats.formatted()) sats → instant")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                    .widgetURL(context.state.phase.deepLink)
                }
            } compactLeading: {
                Image(systemName: "bolt.fill").foregroundStyle(bittrYellow)
                    .widgetURL(context.state.phase.deepLink)
            } compactTrailing: {
                TimerOrIcon(state: state, compact: true)
                    .widgetURL(context.state.phase.deepLink)
            } minimal: {
                Image(systemName: state.phase.showsTimer ? "bolt.fill" : state.phase.systemIcon)
                    .foregroundStyle(state.phase.tint)
                    .widgetURL(context.state.phase.deepLink)
            }
            .keylineTint(bittrYellow)
        }
    }
}
