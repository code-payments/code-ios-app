//
//  PinBar.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The pinned message under the navigation bar, drawn as the composer's reply strip quotes a
/// message: the author's rule, their name, and one line or a thumbnail of what they said. With more
/// than one pin the rule shows segments, the shown pin's lit. Tapping the bar jumps to that message;
/// the list button opens every pin.
struct PinBar: View {

    /// The pin the bar shows, quoted as a reply would quote it.
    let quote: ChatQuote
    /// How many pins the viewer can see, which the rule's segments count.
    let count: Int
    /// Where the shown pin sits among them, newest first.
    let index: Int
    /// Where a pinned photo's thumbnail loads from.
    var thumbnailLocation: (ChatQuote.Kind) async -> ChatMediaLocation? = { _ in nil }
    let onTap: () -> Void
    let onList: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    PinBarRule(count: count, index: index, color: ComplementaryPalette.nameColor(for: quote.authorID))
                    ChatQuoteContent(
                        authorName: quote.authorName,
                        authorID: quote.authorID,
                        snippet: quote.snippet,
                        kind: quote.kind,
                        snippetLines: 1,
                        thumbnailLocation: thumbnailLocation,
                        textVerticalPadding: 0
                    )
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pinned message from \(quote.authorName): \(ChatQuoteContent.spokenSnippet(quote.snippet, kind: quote.kind))")
            .accessibilityHint("Shows the message in the chat")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("pin-bar")

            Button(action: onList) {
                Image.asset(.listBulletPin)
                    .foregroundStyle(Color.textMain)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pinned Messages")
            .accessibilityIdentifier("pin-bar-list")
        }
        // The rule and the list button fill the bar's height, not the overlay's.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: BarMetrics.contentHeight)
        .contentShape(.rect(cornerRadius: BarMetrics.cornerRadius))
        // Darker than the reply strip's glass: the transcript scrolls under it and washed its text out.
        .overlayGlassBackground(in: .rect(cornerRadius: BarMetrics.cornerRadius))
    }
}

/// Which pins the bar's rule shows and which is lit. Segments fill bottom up: the newest pin is
/// the bottom segment and each tap lights the next one up. The window fits two segments; past
/// two pins the track scrolls so the lit one stays in view.
struct PinBarSegments: Equatable {

    /// Pin indices in the window, newest first, so the last is the top segment.
    let visible: [Int]
    /// The pin index whose segment is lit.
    let lit: Int

    /// The pin index of the window's top segment.
    var top: Int { visible[visible.count - 1] }

    /// Segments the window fits.
    static let windowSize = 2

    /// The window for `count` pins showing the pin at `index` (0 is newest), or nil for one pin,
    /// which keeps a single unbroken rule.
    init?(count: Int, index: Int) {
        guard count > 1 else { return nil }
        let lit = min(max(index, 0), count - 1)
        let bottom = min(max(lit - 1, 0), count - Self.windowSize)
        self.visible = Array(bottom..<(bottom + Self.windowSize))
        self.lit = lit
    }
}

/// The author's rule down the quote's leading edge. With more than one pin it is a window onto a
/// track of one segment per pin, as Telegram marks which pin a cycling bar is on.
private struct PinBarRule: View {

    let count: Int
    let index: Int
    let color: Color

    private static let width: CGFloat = 3
    private static let segmentHeight: CGFloat = 16
    private static let gap: CGFloat = 2
    private static let windowHeight: CGFloat = segmentHeight * CGFloat(PinBarSegments.windowSize) + gap

    var body: some View {
        Group {
            if let segments = PinBarSegments(count: count, index: index) {
                // Top to bottom the track runs oldest to newest; its offset scrolls the window.
                VStack(spacing: Self.gap) {
                    ForEach((0..<count).reversed(), id: \.self) { pin in
                        Capsule()
                            .fill(pin == segments.lit ? color : Color.textSecondary.opacity(0.4))
                            .frame(width: Self.width, height: Self.segmentHeight)
                    }
                }
                .offset(y: -CGFloat(count - 1 - segments.top) * (Self.segmentHeight + Self.gap))
                .frame(width: Self.width, height: Self.windowHeight, alignment: .top)
                .clipped()
                .animation(.easeInOut(duration: 0.25), value: segments)
            } else {
                Capsule()
                    .fill(color)
                    .frame(width: Self.width)
                    .frame(maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The pin button in the navigation bar's trailing slot while the request strip holds the slot
/// under the bar. Opens every pin.
struct PinToolbarButton: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image.asset(.listBulletPin)
                .foregroundStyle(Color.textMain)
                .frame(width: Metrics.buttonHeightThin, height: Metrics.buttonHeightThin)
                .overlayGlassBackground(in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel("Pinned Messages")
        .accessibilityIdentifier("pin-toolbar-button")
    }
}
