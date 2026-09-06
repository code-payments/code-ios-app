//
//  ComposerReplyStrip.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The quoted original above the composer while a reply is being written: a rule in the author's own
/// colour flush against the screen's leading edge, their name over one or two lines of what they
/// said, and the way out on the trailing edge. Dismissing it takes back the target without touching
/// the draft.
///
/// No card and no tinted ground. The strip is not a thing sitting on the bar, it *is* the top of the
/// bar — the rule runs the full height of the region the bar grew by, edge to edge, which is what
/// makes the growth read as the bar getting taller rather than as a panel arriving. Matches
/// WhatsApp, measured: 4pt rule at x=0, text 13pt in, no inset of any kind.
///
/// The colour is the person's, not the surface's — `ComplementaryPalette` derives it from their user
/// id, so the same person is the same colour here, inside a sent bubble, and on Android.
struct ComposerReplyStrip: View {

    let target: ComposerModel.ReplyTarget
    let onDismiss: () -> Void

    /// Flush at the screen's leading edge, so it reads as a citation mark on the bar rather than a
    /// border on a card.
    private static let ruleWidth: CGFloat = 4

    /// Sized to the cap height of the amount beside it, so the flag reads as a mark on the line
    /// rather than as a second element the line has to make room for.
    private static let flagDiameter: CGFloat = 16

    var body: some View {
        let rule = ComplementaryPalette.color(.start, for: target.authorID)
        let name = ComplementaryPalette.color(.middle, for: target.authorID)

        HStack(alignment: .center, spacing: 9) {
            // Unpadded and unclipped: a `Rectangle` is flexible vertically, so in this stack it
            // takes the strip's whole height, and with no leading padding on the row it starts at
            // the screen edge.
            Rectangle()
                .fill(rule)
                .frame(width: Self.ruleWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.authorName)
                    .font(.appTextHeading)
                    .foregroundStyle(name)
                quoteLine
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Combined here rather than on the row, so the quote reads as one element while the
            // dismiss button stays a button of its own — a row-level combine folds the button into
            // the label and leaves nothing to press.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Replying to \(target.authorName): \(spokenSnippet)")
            .accessibilityIdentifier("composer-reply-quote")

            // WhatsApp's: a large, thin ✕ rather than a small bold one, sized to sit against two
            // lines of quote without crowding them, in a hit target wider than the glyph.
            Button(action: onDismiss) {
                Image(systemName: SystemSymbol.close.rawValue)
                    // `.system`, not the app face: the stroke weight is the point of the match, and
                    // an SF Symbol only takes a weight axis from a system font.
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
            .accessibilityIdentifier("cancel-reply-button")
        }
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer-reply-strip")
    }

    /// The quoted original itself. One step under the bubble body's 16, and in the same weight: the
    /// quote is the subject of the strip, so it is read, not glanced at. `textMain` for the same
    /// reason — dimming it made it look like placeholder text for the field below.
    ///
    /// A payment carries the flag and the mint's name the cash card leads with. The amount alone
    /// reads as a number; with the flag beside it, it reads as the payment being answered.
    @ViewBuilder
    private var quoteLine: some View {
        switch target.kind {
        case .cash(let token, let flagImageName):
            HStack(spacing: 6) {
                if let flag = flagImageName.flatMap(Image.cashFlag(named:)) {
                    flag
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.flagDiameter, height: Self.flagDiameter)
                        .clipShape(.circle)
                }
                Text(target.snippet)
                    .font(.default(size: 14, weight: .medium))
                    .foregroundStyle(Color.textMain)
                Text(token)
                    .font(.default(size: 14, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .lineLimit(1)
        case .text, .unavailable:
            Text(target.snippet)
                .font(.default(size: 14, weight: .medium))
                .foregroundStyle(Color.textMain)
                .lineLimit(2)
        }
    }

    /// What VoiceOver reads for the quote — the mint's name is part of a payment's identity, and it
    /// is drawn as a separate run that the combined element would otherwise drop.
    private var spokenSnippet: String {
        switch target.kind {
        case .cash(let token, _):  "\(target.snippet) \(token)"
        case .text, .unavailable:  target.snippet
        }
    }
}
