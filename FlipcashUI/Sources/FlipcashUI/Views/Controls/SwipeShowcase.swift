//
//  SwipeShowcase.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

/// The swipe-to-send prototype, standing in for the whole app when launched with `--swipe-sandbox`.
///
/// A launch argument for the same reason as the tray sandbox: one `simctl launch` line puts the
/// device on the swipe controls with no sign-in. DEBUG-only, so it can't ship.
public enum SwipeSandbox {

    /// Whether the app was launched with `--swipe-sandbox`. // LOCAL-TUNER
    @MainActor public static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--swipe-sandbox") // LOCAL-TUNER
    }
}

/// Every look of the swipe control side by side at the send screen's width, each driven by a
/// local closure that succeeds, fails or is disabled, so the looks can be felt without sending.
public struct SwipeShowcaseScreen: View {

    @State private var outcome: SwipeShowcaseOutcome = .succeeds
    @State private var isLongLabel = false

    /// Creates the showcase.
    public init() {}

    public var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                controls
                Spacer(minLength: 24)
                looks
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Controls -

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Outcome", selection: $outcome) {
                ForEach(SwipeShowcaseOutcome.allCases) { outcome in
                    Text(outcome.title).tag(outcome)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Long label", isOn: $isLongLabel)
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)

            Text("Hold three fingers to open the tuner → Swipe") // LOCAL-TUNER
                .font(.appTextCaption) // LOCAL-TUNER
                .foregroundStyle(Color.textSecondary) // LOCAL-TUNER
        }
    }

    // MARK: - Looks -

    private var looks: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(SwipeControlLook.allCases, id: \.self) { look in // LOCAL-TUNER
                VStack(alignment: .leading, spacing: 10) {
                    Text(look.showcaseCaption) // LOCAL-TUNER
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)

                    SwipeControl(text: label, action: outcome.action)
                        .swipeControlLook(look) // LOCAL-TUNER
                        .disabled(outcome == .disabled)
                }
            }
        }
    }

    private var label: String {
        isLongLabel ? "Swipe to Send $1,250.00 to Alexandra" : "Swipe to Send"
    }
}

// MARK: - Outcome -

/// What a showcase swipe does once it commits; every outcome is a local sleep, never a send.
public enum SwipeShowcaseOutcome: String, CaseIterable, Identifiable {
    case succeeds
    case fails
    case disabled

    public var id: String { rawValue }

    /// The outcome's name in the showcase's picker.
    public var title: String {
        switch self {
        case .succeeds: "Succeeds"
        case .fails: "Fails"
        case .disabled: "Disabled"
        }
    }

    /// The swipe's action: succeeds after a beat, or fails with ``SwipeControlFailure``.
    public var action: ThrowingAction {
        switch self {
        case .succeeds, .disabled:
            return {
                try await Task.sleep(for: .seconds(1.5))
            }
        case .fails:
            return {
                try await Task.sleep(for: .seconds(1))
                throw SwipeControlFailure()
            }
        }
    }
}

// MARK: - Look captions -

extension SwipeControlLook { // LOCAL-TUNER

    /// The look's letter and name, e.g. "C · Lens". // LOCAL-TUNER
    public var showcaseCaption: String { // LOCAL-TUNER
        switch self { // LOCAL-TUNER
        case .glassThumb: "A · Glass thumb" // LOCAL-TUNER
        case .morphFill: "B · Thumb becomes the button" // LOCAL-TUNER
        case .lens: "C · Lens" // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER

    /// The look's letter alone, for a compact picker. // LOCAL-TUNER
    public var showcaseLetter: String { // LOCAL-TUNER
        String(showcaseCaption.prefix(1)) // LOCAL-TUNER
    } // LOCAL-TUNER
} // LOCAL-TUNER

#Preview("Swipe showcase") {
    SwipeShowcaseScreen()
}
#endif
