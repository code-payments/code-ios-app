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
/// message: the author's rule, their name, and one line or a thumbnail of what they said. The rule
/// splits into one segment per pin, with the shown pin's lit. Tapping the bar jumps to that message;
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

/// The author's rule down the quote's leading edge, split into one segment per pin with the shown
/// one lit, as Telegram marks which pin a cycling bar is on. One pin is one unbroken rule.
private struct PinBarRule: View {

    let count: Int
    let index: Int
    let color: Color

    private static let width: CGFloat = 3
    private static let gap: CGFloat = 2

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(0..<max(count, 1), id: \.self) { segment in
                Capsule()
                    .fill(segment == index ? color : Color.textSecondary.opacity(0.4))
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
