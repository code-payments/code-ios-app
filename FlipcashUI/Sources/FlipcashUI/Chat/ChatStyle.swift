//
//  ChatStyle.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The chat transcript's look: bubble shape and type, sender colours, row spacing, the money card
/// and reaction pills. Values come from the Chat v2 design (Figma `v2/Platform` iOS, `v2/Color`
/// Dark); every transcript surface reads them from here so one change lands everywhere at once.
enum ChatStyle {

    // MARK: - Bubble

    /// A bubble's corner radius, capped at the capsule radius (half the bubble's height), so a
    /// one-line bubble is a pill and a taller one keeps this radius.
    static let bubbleRadius: CGFloat = 20
    /// The inner corner where two bubbles of one sender's run meet.
    static let joinedRadius: CGFloat = 20
    /// Text inset from a bubble's leading and trailing edges.
    static let bubblePaddingX: CGFloat = 14
    /// Text inset from a bubble's top and bottom edges.
    static let bubblePaddingY: CGFloat = 10
    /// How a bubble's corners curve.
    static let cornerStyle: RoundedCornerStyle = .continuous
    /// Message body point size.
    static let bodySize: CGFloat = 17
    /// Message body weight.
    static let bodyWeight: UIFont.Weight = .regular
    /// Message body line height.
    static let bodyLineHeight: CGFloat = 22
    /// Whether bubbles draw the faint hairline outline the v1 chat had.
    static let drawsHairline = false
    /// The widest a bubble may grow, as a share of the transcript's width.
    static let maxWidthFraction = ChatPhotoBubbleLayout.widthFraction

    /// The message body font.
    static let bodyFont: UIFont = .default(size: bodySize, weight: bodyWeight)

    /// Paragraph attributes that hold `font` to the body's line height, with the extra leading
    /// split above and below the glyphs rather than all of it landing on top.
    static func bodyLineAttributes(for font: UIFont) -> [NSAttributedString.Key: Any] {
        let lineHeight = max(bodyLineHeight, font.lineHeight)
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return [.paragraphStyle: style, .baselineOffset: (lineHeight - font.lineHeight) / 4]
    }

    // MARK: - Colour

    /// How the sent bubble is drawn in the light appearance. Dark is the same in both: the focus
    /// blue at 32% with near-white blue text.
    enum LightSentBubble {
        /// The focus blue at 16% over the page with deep navy text: the dark bubble's one-hue
        /// recipe turned over.
        case accentTint
        /// Figma's ink proposal: near-black at 14% with near-black text.
        case ink
    }

    /// The light sent bubble in use: `.accentTint`, or `.ink` to try Figma's proposal.
    static let lightSentBubble: LightSentBubble = .accentTint

    /// The sent bubble's fill and ink in the light appearance, per ``lightSentBubble``.
    private static var lightSent: (fill: Color, ink: Color) {
        switch lightSentBubble {
        case .accentTint: (Color(r: 0, g: 122, b: 255).opacity(0.16), Color(r: 0, g: 26, b: 64))
        case .ink:        (Color(r: 17, g: 17, b: 19).opacity(0.14), Color(r: 17, g: 17, b: 19))
        }
    }

    /// The sent bubble's ink in each appearance, at full strength.
    private static let sentInk = (
        light: lightSent.ink,
        dark: Color(uiColor: UIColor(displayP3Red: 0.88, green: 0.94, blue: 1, alpha: 1))
    )
    /// The received bubble's ink in each appearance, at full strength.
    private static let receivedInk = (light: Color.black, dark: Color.white)

    /// The sent bubble's fill: the accent, faint over the conversation background.
    static let sentFill = UIColor(Color(light: lightSent.fill, dark: Color(r: 10, g: 132, b: 255).opacity(0.32)))
    /// Text on a sent bubble: in dark, the accent at full saturation lifted most of the way to
    /// white, in Display P3 so it glows against the faint fill; in light, the same hue taken most of
    /// the way to black.
    static let sentText = UIColor(Color(light: sentInk.light, dark: sentInk.dark))
    /// The received bubble's fill: `#232325` in dark, Messages' `#E9E9EB` in light.
    static let receivedFill = UIColor(Color(light: Color(r: 233, g: 233, b: 235), dark: Color(r: 35, g: 35, b: 37)))
    /// Text on a received bubble.
    static let receivedText = UIColor(Color.textMain)
    /// Secondary text in the transcript: captions, the money card's labels, a resting reaction
    /// count. Apple's secondary label in dark; in light the same grey a step deeper, so it keeps
    /// 4.5:1 on a pill or the money card.
    static let secondaryText = UIColor(Color(
        light: Color(r: 60, g: 60, b: 67, o: 0.8),
        dark: Color(r: 235, g: 235, b: 245).opacity(0.6)
    ))
    /// The tint under a reaction the viewer added.
    static let accentTint = UIColor(Color(
        light: Color(r: 0, g: 122, b: 255).opacity(0.1),
        dark: Color(r: 10, g: 132, b: 255).opacity(0.16)
    ))
    /// The ring around a reaction the viewer added.
    static let accentRing = UIColor(Color(
        light: Color(r: 0, g: 122, b: 255).opacity(0.5),
        dark: Color(r: 10, g: 132, b: 255).opacity(0.5)
    ))
    /// The accent for text and glyphs: the focus blue, a step deeper in light so a count on
    /// ``accentTint`` keeps 4.5:1.
    static let accentColor = UIColor(Color(light: Color(r: 0, g: 98, b: 204), dark: Color(r: 10, g: 132, b: 255)))

    /// Quiet transcript text — the date line, receipts, a group author's name: white at 50% in
    /// dark, black at 60% in light, where 50% falls under 4.5:1.
    static let quiet = ink(dark: 0.5, light: 0.6)
    /// ``quiet`` for UIKit.
    static let quietText = UIColor(quiet)

    /// The count on a boosted pill the viewer reacted to: the boost gold at 50% in dark, and the
    /// full gold in light, where any fade falls under 4.5:1 on the pill.
    static let boostCount = UIColor(Color(
        light: Color(r: 143, g: 98, b: 0),
        dark: Color(r: 255, g: 200, b: 40).opacity(0.5)
    ))

    /// Transcript ink at a strength per appearance: white at `dark` in the dark appearance, black at
    /// `light` in light.
    static func ink(dark: Double, light: Double) -> Color {
        Color(light: .black.opacity(light), dark: .white.opacity(dark))
    }

    /// ``ink(dark:light:)`` for UIKit.
    static func uiInk(dark: Double, light: Double) -> UIColor {
        UIColor(ink(dark: dark, light: light))
    }

    /// A bubble's fill for its sender.
    static func fill(isFromSelf: Bool) -> UIColor {
        isFromSelf ? sentFill : receivedFill
    }

    /// Body text colour on a sender's bubble.
    static func text(isFromSelf: Bool) -> UIColor {
        isFromSelf ? sentText : receivedText
    }

    /// Body text on a sender's bubble faded to `dark` in the dark appearance and to `light` in
    /// light, where a pale bubble needs a lighter fade to keep 4.5:1.
    static func text(isFromSelf: Bool, dark: Double, light: Double) -> UIColor {
        let ink = isFromSelf ? sentInk : receivedInk
        return UIColor(Color(light: ink.light.opacity(light), dark: ink.dark.opacity(dark)))
    }

    private static let mutedSent = text(isFromSelf: true, dark: 0.6, light: 0.7)
    private static let mutedReceived = text(isFromSelf: false, dark: 0.6, light: 0.7)

    /// Muted text on a sender's bubble: a placeholder, a quote's snippet, the "Edited" marker.
    static func mutedText(isFromSelf: Bool) -> UIColor {
        isFromSelf ? mutedSent : mutedReceived
    }

    // MARK: - Group names

    /// A group author's name above their first bubble.
    static let authorNameSize: CGFloat = 12
    /// A group author's name weight.
    static let authorNameWeight: UIFont.Weight = .regular

    // MARK: - Avatars

    /// A hairline ring around avatars, so a dark photo still reads as a circle.
    static let avatarStrokeWidth: CGFloat = 1
    /// How much white the avatar ring takes.
    static let avatarStrokeOpacity: CGFloat = 0.05
    /// The avatar ring: white at ``avatarStrokeOpacity`` in dark, black at 5% in light, so a light
    /// photo still reads as a circle.
    static let avatarStroke = UIColor(Color(light: .black.opacity(0.05), dark: .white.opacity(avatarStrokeOpacity)))
    /// The avatar beside a group author's first bubble.
    static let authorAvatarSize: CGFloat = 28

    // MARK: - Swipe to reply

    /// The reply arrow that follows a swiped row.
    static let replyIconSize: CGFloat = 24
    /// The reply arrow's colour: white at 40% in dark, black at 50% in light, for 3:1 on the page.
    static let replyIconColor = ink(dark: 0.4, light: 0.5)

    // MARK: - Mentions

    /// An `@handle`'s point size, a step under the body's.
    static let mentionSize: CGFloat = 12.5
    /// An `@handle`'s weight.
    static let mentionWeight: UIFont.Weight = .semibold
    /// How far an `@handle` rises past centring its capitals on the body's.
    static let mentionBaselineNudge: CGFloat = 0.5
    /// An `@handle`'s text colour, the same on either sender's bubble.
    static let mentionText = uiInk(dark: 0.77, light: 0.77)

    // MARK: - Spacing

    /// Between two bubbles of one sender's run.
    static let runGap: CGFloat = 4
    /// Between two messages of one sender that the grouping window broke apart, and around a date.
    static let momentGap: CGFloat = 10
    /// Between two speakers.
    static let speakerGap: CGFloat = 16
    /// The transcript's side margin.
    static let rowInset: CGFloat = 16

    // MARK: - Money card

    /// The money card's fill: neutral, so money reads the same under any accent. `#1C1C1E` in dark,
    /// the raised `#F2F2F7` in light, where its text flips with it.
    static let cardFill = UIColor(Color(light: Color(r: 242, g: 242, b: 247), dark: Color(r: 28, g: 28, b: 30)))
    /// The money card's corner radius.
    static let cardRadius: CGFloat = 22
    /// The money card's width.
    static let cardWidth: CGFloat = 240
    /// The money card's inset from its leading and trailing edges.
    static let cardPaddingX: CGFloat = 16
    /// Above the caption.
    static let cardPaddingTop: CGFloat = 14
    /// Below the counterpart, to the card's foot or the Send Back row.
    static let cardPaddingBottom: CGFloat = 22
    /// Between the caption, the money block and the counterpart.
    static let cardBlockGap: CGFloat = 14
    /// The token's icon, beside its name under the amount.
    static let cardBadgeSize: CGFloat = 20
    /// The card's label point size.
    static let cardLabelSize: CGFloat = 13
    /// The card's amount point size.
    static let cardAmountSize: CGFloat = 34

    // MARK: - Reactions

    /// A reaction pill's height.
    static let pillHeight: CGFloat = 32
    /// Between a pill's leading edge and its emoji.
    static let pillLeadingPadding: CGFloat = 10
    /// Between a pill's count and its trailing edge.
    static let pillTrailingPadding: CGFloat = 2
    /// Between pills, and between the message and its pills.
    static let pillGap: CGFloat = 4
    /// Between a pill's emoji and its count.
    static let pillInnerGap: CGFloat = 4
    /// The most digits a pill's count reserves room for.
    static let pillCountRoom = 2
    /// A pill's emoji point size.
    static let pillEmojiSize: CGFloat = 13
    /// A pill's count point size.
    static let pillCountSize: CGFloat = 13
    /// The width of the ring around a reaction the viewer added.
    static let pillRingWidth: CGFloat = 1.75
    /// A reaction nobody here added: white at 9% in dark, Apple's tertiary fill in light.
    static let pillFill = UIColor(Color(light: Color(r: 118, g: 118, b: 128, o: 0.12), dark: .white.opacity(0.09)))
    /// Whether the add-reaction button sits on a glass circle, as in v1.
    static let addReactionGlass = false
    /// The add-reaction glyph.
    static let addReactionIconSize: CGFloat = 19.3
}
#endif
