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
/// colour, the author's name over one or two lines of what they said, and the way out on the
/// trailing edge. Dismissing it takes back the target without touching the draft.
///
/// The quote carries the reply's elevation, because the bar cannot. The bar's slab has to stay the
/// chat background to match the keyboard it sits on — see `BarSurfaceBackground` — so the ground
/// that sets a reply apart is drawn here, inset from the bar's edges, in one of two ``Style``s.
///
/// The colour is the person's, not the surface's — `ComplementaryPalette` derives it from their user
/// id, so the same person is the same colour here, inside a sent bubble, and on Android.
struct ComposerReplyStrip: View {

    /// The container the quote is drawn in.
    ///
    /// Both keep the bar's slab flat, so neither draws a line against the keyboard; they differ in
    /// whether the quote reads as part of the bar or as something floating over it.
    enum Style {
        /// An opaque panel on the bar's own surface, one step up from it. The conservative reading
        /// of WhatsApp: a reply makes the bar taller and puts a card in the space it gained.
        case panel
        /// A Liquid Glass capsule floating clear of the bar, sampling the transcript behind it.
        /// Falls back to an ultra-thin material below iOS 26.
        case glass
    }

    let target: ComposerModel.ReplyTarget
    let onDismiss: () -> Void

    /// Prototype switch, read from the shared instance rather than the environment: the bar is
    /// hosted inside a `UIHostingController`, which does not inherit the app's SwiftUI environment.
    /// `BetaFlags` is `@Observable`, so reading it in `body` still re-renders on the toggle.
    private var style: Style {
        BetaFlags.shared.hasEnabled(.glassReplyQuote) ? .glass : .panel
    }

    private static let ruleWidth: CGFloat = 4

    /// How far the quote's ground is held off the bar's own edges, matching the composer row's
    /// horizontal padding below it so the two stack up on one margin.
    private static let inset: CGFloat = 12

    /// Sized to the cap height of the amount beside it, so the flag reads as a mark on the line
    /// rather than as a second element the line has to make room for.
    private static let flagDiameter: CGFloat = 16

    var body: some View {
        let rule = ComplementaryPalette.color(.start, for: target.authorID)
        let name = ComplementaryPalette.color(.middle, for: target.authorID)

        HStack(alignment: .center, spacing: 9) {
            authorRule(rule)

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
        .padding(.trailing, style == .glass ? 12 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(QuoteGround(style: style))
        .padding(.horizontal, Self.inset)
        // Clear of the composer row below and of the bar's top edge above, so the ground reads as a
        // thing on the bar rather than as the bar's own top.
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer-reply-strip")
    }

    /// The author's colour down the leading edge of the quote.
    ///
    /// A `Rectangle` is flexible vertically, so in the row it takes the quote's whole height. The
    /// panel clips it to the corner radius, which is what keeps it flush; the capsule cannot clip a
    /// square rule against a curve without it reading as a chip out of the glass, so there it is a
    /// rounded rule held inside the curve.
    @ViewBuilder
    private func authorRule(_ color: Color) -> some View {
        switch style {
        case .panel:
            Rectangle()
                .fill(color)
                .frame(width: Self.ruleWidth)
        case .glass:
            Capsule()
                .fill(color)
                .frame(width: Self.ruleWidth)
                .padding(.vertical, 8)
                .padding(.leading, 12)
        }
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

/// What the quote sits on, and the clip that goes with it.
///
/// The panel has to clip its content as well as fill behind it: the author's rule runs flush to the
/// leading edge, and unclipped it squares off the two corners it passes. The capsule must *not*
/// clip — `glassEffect` draws its specular edge and shadow outside its own bounds, and a clip
/// shaves them off, leaving a flat grey pill. The rule is inset for the capsule for the same reason.
private struct QuoteGround: ViewModifier {

    let style: ComposerReplyStrip.Style

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .panel:
            content
                .background(Color.backgroundSecondary)
                .clipShape(.rect(cornerRadius: BarMetrics.cornerRadius))
        case .glass:
            content.glassCapsuleBackground()
        }
    }
}
