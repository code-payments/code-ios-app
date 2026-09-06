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
    /// Both keep the bar's slab flat, so neither draws a line against the keyboard, and both take
    /// `BarMetrics.cornerRadius` — the field's and the Send Cash button's — so the quote is the same
    /// shape as everything else on the bar. What differs is the material, and so what the quote
    /// reads as: part of the bar, or something floating over it.
    enum Style {
        /// An opaque card over the transcript, one step up from the chat background. The
        /// conservative reading of WhatsApp, minus its slab: the bar's surface stops at the composer
        /// row, so the card is what the reply adds.
        case panel
        /// Liquid Glass floating clear of the bar, sampling the transcript behind it. Falls back to
        /// an ultra-thin material below iOS 26.
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

    /// Wider than the 4pt a blockquote rule usually takes, because the quote's corner radius is the
    /// bar's 14: the leading edge is straight for only `contentHeight - 14 * 2` of its run, and the
    /// corners taper the rest away. Thickness can't lengthen that straight core — it only gives the
    /// tapered ends enough mass to read as caps rather than as a clipping accident.
    private static let ruleWidth: CGFloat = 6

    /// The gap after the rule, and between the quote and the button that dismisses it.
    private static let gutter: CGFloat = 9

    /// The margin around the quote's ground, on every side: matching the composer row's horizontal
    /// padding below it, so the two stack up on one margin and the quote is inset by the same amount
    /// from the bar's edges as it is from the controls.
    private static let inset: CGFloat = 12

    /// Sized to the cap height of the amount beside it, so the flag reads as a mark on the line
    /// rather than as a second element the line has to make room for.
    private static let flagDiameter: CGFloat = 16

    var body: some View {
        let rule = ComplementaryPalette.color(.start, for: target.authorID)
        let name = ComplementaryPalette.color(.middle, for: target.authorID)

        HStack(alignment: .center, spacing: Self.gutter) {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.authorName)
                    .font(.appTextHeading)
                    .foregroundStyle(name)
                quoteLine
            }
            .padding(.vertical, BarMetrics.fieldVerticalPadding)
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
        // Where the rule and its gutter used to stand in the row.
        .padding(.leading, Self.ruleWidth + Self.gutter)
        .padding(.trailing, 8)
        // The Send Cash button's height, so a one-line quote is the same size box as the controls
        // below it. Only a minimum: a snippet that wraps to a second line has to grow, and the two
        // fonts stacked here land a point under the controls on their own, which is close enough to
        // read as a mistake rather than as a different size.
        .frame(maxWidth: .infinity, minHeight: BarMetrics.contentHeight, alignment: .leading)
        // Overlaid on the pinned frame rather than standing in the row, so it spans the quote's real
        // height. As a row member it took the row's natural height instead, which the frame above then
        // centred inside `contentHeight` — leaving the rule a fraction short at both ends.
        // ``QuoteGround`` rounds off the two corners it passes.
        .overlay(alignment: .leading) {
            QuoteRule(color: rule, style: style)
                .frame(width: Self.ruleWidth)
        }
        .modifier(QuoteGround(style: style))
        .padding(.horizontal, Self.inset)
        // One margin all the way round: the quote sits ``inset`` from the bar's top edge and the same
        // distance off the controls below. The bar already pads its own row, so only the remainder is
        // added here — padding both by ``inset`` would leave the gap underneath twice the one above.
        .padding(.top, Self.inset)
        .padding(.bottom, Self.inset - BarMetrics.contentPadding)
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

/// The author's colour down the quote's leading edge, in the same material as the ground behind it:
/// a solid fill on the opaque card, tinted Liquid Glass on the glass. A solid bar over glass reads as
/// a sticker stuck to the surface rather than as part of it.
private struct QuoteRule: View {

    let color: Color
    let style: ComposerReplyStrip.Style

    @ViewBuilder
    var body: some View {
        switch style {
        case .panel:
            Rectangle().fill(color)
        case .glass:
            // Square-cornered: ``QuoteGround``'s clip rounds the two corners this rule passes.
            Color.clear.glassBackground(cornerRadius: 0, tint: color)
        }
    }
}

/// What the quote sits on. One radius — the bar's — and two materials.
///
/// The clip goes on the content and the ground goes behind it, rather than one clip over both. Both
/// halves need that. The author's rule runs flush to the leading edge and squares off the two
/// corners it passes unless something rounds it, and `glassEffect` draws its specular edge outside
/// its own bounds and loses it to a clip — so the rule is clipped, the ground is not, and the rule
/// can sit on the edge in either style.
private struct QuoteGround: ViewModifier {

    let style: ComposerReplyStrip.Style

    private static let shape = RoundedRectangle(cornerRadius: BarMetrics.cornerRadius)

    @ViewBuilder
    func body(content: Content) -> some View {
        let quote = content.clipShape(Self.shape)
        switch style {
        case .panel:
            quote.background(Color.backgroundSecondary, in: Self.shape)
        case .glass:
            // The background form, not the wrapping one: the glass has to stay outside the clip.
            quote.glassFieldBackground(cornerRadius: BarMetrics.cornerRadius)
        }
    }
}
