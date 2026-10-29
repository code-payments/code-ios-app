//
//  ChatStyle.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

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
    static let maxWidthFraction: CGFloat = 0.78

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

    /// The transcript's accent: the app's focus blue.
    static let accent = Color.badgeFocus
    /// The sent bubble's fill: the accent, faint over the conversation background.
    static let sentFill = UIColor(accent.opacity(0.32))
    /// Text on a sent bubble: the accent at full saturation lifted most of the way to white, in
    /// Display P3 so it glows against the faint fill.
    static let sentText = UIColor(displayP3Red: 0.88, green: 0.94, blue: 1, alpha: 1)
    /// The received bubble's fill.
    static let receivedFill = UIColor(Color(r: 35, g: 35, b: 37))
    /// Text on a received bubble.
    static let receivedText = UIColor.white
    /// Secondary text in the transcript: captions, the money card's labels, a resting reaction count.
    static let secondaryText = UIColor(Color(r: 235, g: 235, b: 245).opacity(0.6))
    /// The tint under a reaction the viewer added.
    static let accentTint = UIColor(accent.opacity(0.16))
    /// The ring around a reaction the viewer added.
    static let accentRing = UIColor(accent.opacity(0.5))
    /// The accent itself, for text and glyphs.
    static let accentColor = UIColor(accent)

    /// A bubble's fill for its sender.
    static func fill(isFromSelf: Bool) -> UIColor {
        isFromSelf ? sentFill : receivedFill
    }

    /// Body text colour on a sender's bubble.
    static func text(isFromSelf: Bool) -> UIColor {
        isFromSelf ? sentText : receivedText
    }

    /// Muted text on a sender's bubble: a placeholder, a quote's snippet, the "Edited" marker.
    static func mutedText(isFromSelf: Bool) -> UIColor {
        text(isFromSelf: isFromSelf).withAlphaComponent(0.6)
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
    /// The avatar beside a group author's first bubble.
    static let authorAvatarSize: CGFloat = 28

    // MARK: - Swipe to reply

    /// The reply arrow that follows a swiped row.
    static let replyIconSize: CGFloat = 24
    /// The reply arrow's colour.
    static let replyIconColor = Color.white.opacity(0.4)

    // MARK: - Mentions

    /// An `@handle`'s point size, a step under the body's.
    static let mentionSize: CGFloat = 12.5
    /// An `@handle`'s weight.
    static let mentionWeight: UIFont.Weight = .semibold
    /// How far an `@handle` rises past centring its capitals on the body's.
    static let mentionBaselineNudge: CGFloat = 0.5
    /// An `@handle`'s text colour, the same on either sender's bubble.
    static let mentionText = UIColor(Color.white.opacity(0.77))

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

    /// The money card's fill: neutral, so money reads the same under any accent.
    static let cardFill = UIColor(Color(r: 28, g: 28, b: 30))
    /// The money card's corner radius.
    static let cardRadius: CGFloat = 22
    /// The money card's width.
    static let cardWidth: CGFloat = 240
    /// The money card's inset from its leading and trailing edges.
    static let cardPaddingX: CGFloat = 16
    /// The money card's inset above its header.
    static let cardPaddingTop: CGFloat = 14
    /// The money card's inset below its amount.
    static let cardPaddingBottom: CGFloat = 22
    /// Between the card's header and its caption.
    static let cardHeaderGap: CGFloat = 14
    /// The token badge in the header.
    static let cardBadgeSize: CGFloat = 20
    /// The card's label point size.
    static let cardLabelSize: CGFloat = 13
    /// The card's amount point size.
    static let cardAmountSize: CGFloat = 34
    /// The fill behind the cash badge's dollar glyph.
    static let cashBadgeFill = UIColor(Color(r: 48, g: 209, b: 88))

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
    /// A reaction nobody here added.
    static let pillFill = UIColor(Color.white.opacity(0.09))
    /// Whether the add-reaction button sits on a glass circle, as in v1.
    static let addReactionGlass = false
    /// The add-reaction glyph.
    static let addReactionIconSize: CGFloat = 19.3
}
#endif
