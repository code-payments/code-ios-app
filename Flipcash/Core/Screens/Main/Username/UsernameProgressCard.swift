//
//  UsernameProgressCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The You-tab card offering a username, in the tip-card action group below
/// Share/Download (Figma nodes 9536:4336 / 9537:1845). Superseded the
/// settings-row entry point: `YouScreen` shows it only while
/// `shouldPromptForUsername` holds, in place of the row it used to draw.
///
/// Takes plain values rather than reading `Session`/`UsernameGate` itself, so
/// it can be previewed and tested without a signed-in account — the caller
/// (`YouScreen`) is the one place that has both.
struct UsernameProgressCard: View {

    /// Which of the two states the card draws. The title never changes; the
    /// state governs the bar's colour, the chevron, and where the tap lands.
    enum State: Equatable {
        /// Below the server's minimum (node 9536:4336): white bar, the
        /// shortfall in place of a chevron. Tapping raises the balance gate.
        case incomplete
        /// At or above it (node 9537:1845): green bar, chevron. Tapping opens
        /// the claim screen.
        case complete
    }

    private static let title = "Get a custom @username"

    let state: State
    let subtitle: String
    /// The shortfall, shown only in `.incomplete`. `nil` in `.complete`.
    let trailing: String?
    /// The balance's progress toward the minimum, `0...1`.
    let fraction: Double
    /// Runs on tap. Both states are tappable: the card is the entry point to
    /// the flow either way, and below the minimum that means being told the
    /// rule rather than being left with an inert bar.
    let action: VoidAction

    var body: some View {
        Button(action: action) {
            chrome
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.title)
        // The shortfall reads as part of the hint rather than as a value: it
        // is the same sentence the subtitle starts, not a separate reading.
        .accessibilityHint(trailing.map { "\(subtitle). \($0)" } ?? subtitle)
    }

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.title)
                    .font(.default(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textMain)

                if let trailing {
                    Spacer(minLength: 8)
                    Text(trailing)
                        .font(.default(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textMain.opacity(0.5))
                }

                if state == .complete {
                    Spacer(minLength: 8)
                    Image.system(.chevronRight)
                        .renderingMode(.template)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Color.textMain)
                }
            }

            Text(subtitle)
                .font(.default(size: 12, weight: .medium))
                .foregroundStyle(Color.textMain.opacity(0.5))

            Spacer(minLength: 0)

            ProgressTrack(fraction: fraction, fill: state == .complete ? .success : Color.white)
        }
        .padding(.top, 12)
        .padding(.bottom, 15)
        .padding(.horizontal, 15)
        .frame(height: 88)
        .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The card's progress bar: a 10%-white track with a fill sized to `fraction`.
private struct ProgressTrack: View {

    let fraction: Double
    let fill: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.1))

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill)
                    .frame(width: proxy.size.width * CGFloat(max(0, min(1, fraction))))
            }
        }
        .frame(height: 6)
    }
}
