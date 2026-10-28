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

    @State private var outcome: Outcome = .succeeds
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
                ForEach(Outcome.allCases) { outcome in
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
                    Text(Self.caption(for: look)) // LOCAL-TUNER
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)

                    SwipeControl(text: label, action: action)
                        .swipeControlLook(look) // LOCAL-TUNER
                        .disabled(outcome == .disabled)
                }
            }
        }
    }

    private var label: String {
        isLongLabel ? "Swipe to Send $1,250.00 to Alexandra" : "Swipe to Send"
    }

    private var action: ThrowingAction {
        switch outcome {
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

    private static func caption(for look: SwipeControlLook) -> String { // LOCAL-TUNER
        switch look { // LOCAL-TUNER
        case .glassThumb: "A · Glass thumb" // LOCAL-TUNER
        case .morphFill: "B · Thumb becomes the button" // LOCAL-TUNER
        case .lens: "C · Lens" // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER
}

// MARK: - Outcome -

extension SwipeShowcaseScreen {

    /// What the showcase's swipe does once it commits.
    private enum Outcome: String, CaseIterable, Identifiable {
        case succeeds
        case fails
        case disabled

        var id: String { rawValue }

        var title: String {
            switch self {
            case .succeeds: "Succeeds"
            case .fails: "Fails"
            case .disabled: "Disabled"
            }
        }
    }
}

#Preview("Swipe showcase") {
    SwipeShowcaseScreen()
}
#endif
