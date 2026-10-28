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
    static var bubbleRadius: CGFloat { Tuner.value("Chat v2 Bubble/Radius", default: 20, in: 0...44, unit: .points) } // LOCAL-TUNER
    /// The inner corner where two bubbles of one sender's run meet.
    static var joinedRadius: CGFloat { Tuner.value("Chat v2 Bubble/Joined radius", default: 20, in: 0...30, unit: .points) } // LOCAL-TUNER
    /// Text inset from a bubble's leading and trailing edges.
    static var bubblePaddingX: CGFloat { Tuner.value("Chat v2 Bubble/Padding X", default: 14, in: 4...24, unit: .points) } // LOCAL-TUNER
    /// Text inset from a bubble's top and bottom edges.
    static var bubblePaddingY: CGFloat { Tuner.value("Chat v2 Bubble/Padding Y", default: 10, in: 2...16, unit: .points) } // LOCAL-TUNER
    static var cornerStyleChoice: ChatCornerStyle { Tuner.value("Chat v2 Bubble/Corner style", default: ChatCornerStyle.continuous) } // LOCAL-TUNER
    /// How a bubble's corners curve.
    static var cornerStyle: RoundedCornerStyle { cornerStyleChoice.style } // LOCAL-TUNER
    /// Message body point size.
    static var bodySize: CGFloat { Tuner.value("Chat v2 Bubble/Text size", default: 17, in: 13...22, unit: .points) } // LOCAL-TUNER
    static var bodyWeightChoice: ChatTextWeight { Tuner.value("Chat v2 Bubble/Text weight", default: ChatTextWeight.regular) } // LOCAL-TUNER
    /// Message body weight.
    static var bodyWeight: UIFont.Weight { bodyWeightChoice.weight } // LOCAL-TUNER
    /// Message body line height.
    static var bodyLineHeight: CGFloat { Tuner.value("Chat v2 Bubble/Line height", default: 22, in: 16...30, unit: .points) } // LOCAL-TUNER
    /// Whether bubbles draw the faint hairline outline the v1 chat had.
    static var drawsHairline: Bool { Tuner.value("Chat v2 Bubble/Hairline", default: false) } // LOCAL-TUNER
    /// The widest a bubble may grow, as a share of the transcript's width.
    static var maxWidthFraction: CGFloat { Tuner.value("Chat v2 Bubble/Max width", default: 0.78, in: 0.5...0.9, unit: .percent) } // LOCAL-TUNER

    /// The message body font.
    static var bodyFont: UIFont { .default(size: bodySize, weight: bodyWeight) }

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

    static var accent: ChatAccent { Tuner.value("Chat v2 Color/Accent", default: ChatAccent.blue) } // LOCAL-TUNER
    /// The sent bubble's fill: the accent.
    static var sentFill: UIColor { UIColor(accent.color.opacity(sentOpacity)) } // LOCAL-TUNER
    /// How strongly the accent fills a sent bubble, over the conversation background. // LOCAL-TUNER
    static var sentOpacity: Double { Tuner.value("Chat v2 Color/Sent bubble opacity", default: 0.32, in: 0.05...1, unit: .percent) } // LOCAL-TUNER
    /// Text on a sent bubble.
    static var sentText: UIColor { // LOCAL-TUNER
        switch sentTextStyle { // LOCAL-TUNER
        case .white: .white // LOCAL-TUNER
        case .tinted: UIColor(Color.white.mix(with: accent.color, by: sentTextTint)) // LOCAL-TUNER
        case .vivid: vividAccent // LOCAL-TUNER
        case .auto: UIColor(accent.onColor) // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER
    /// The accent pushed toward full brightness, keeping its hue, for text that glows against a faint bubble. // LOCAL-TUNER
    static var vividAccent: UIColor { // LOCAL-TUNER
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0 // LOCAL-TUNER
        UIColor(accent.color).getHue(&h, saturation: &sat, brightness: &b, alpha: &a) // LOCAL-TUNER
        let hsb = UIColor(hue: h, saturation: min(1, sat * vividSaturation), brightness: max(b, vividBrightness), alpha: 1).mixed(withWhite: vividLift) // LOCAL-TUNER
        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0 // LOCAL-TUNER
        hsb.getRed(&r, green: &g, blue: &bl, alpha: &a) // LOCAL-TUNER
        // The same components read in Display P3 land further out than sRGB: the iPhone's own, wider gamut. // LOCAL-TUNER
        return vividInP3 ? UIColor(displayP3Red: r, green: g, blue: bl, alpha: 1) : hsb // LOCAL-TUNER
    } // LOCAL-TUNER
    static var vividSaturation: CGFloat { Tuner.value("Chat v2 Text/Vivid saturation", default: 1.5, in: 0...1.5, unit: .multiplier) } // LOCAL-TUNER
    static var vividBrightness: CGFloat { Tuner.value("Chat v2 Text/Vivid brightness", default: 0.946, in: 0.5...1) } // LOCAL-TUNER
    static var vividInP3: Bool { Tuner.value("Chat v2 Text/Vivid in P3", default: true) } // LOCAL-TUNER
    /// White mixed into vivid text, so a deep accent still reads light. // LOCAL-TUNER
    static var vividLift: CGFloat { Tuner.value("Chat v2 Text/Vivid lift", default: 0.88, in: 0...1, unit: .percent) } // LOCAL-TUNER
    /// A soft accent glow behind sent text; 0 draws none. // LOCAL-TUNER
    static var sentGlowRadius: CGFloat { Tuner.value("Chat v2 Text/Glow radius", default: 0, in: 0...12, unit: .points) } // LOCAL-TUNER
    static var sentGlowOpacity: CGFloat { Tuner.value("Chat v2 Text/Glow opacity", default: 0.8, in: 0...1, unit: .percent) } // LOCAL-TUNER
    /// The glow under sent text, or nil when it is off. // LOCAL-TUNER
    static var sentGlow: NSShadow? { // LOCAL-TUNER
        guard sentGlowRadius > 0 else { return nil } // LOCAL-TUNER
        let glow = NSShadow() // LOCAL-TUNER
        glow.shadowColor = UIColor(accent.color).withAlphaComponent(sentGlowOpacity) // LOCAL-TUNER
        glow.shadowBlurRadius = sentGlowRadius // LOCAL-TUNER
        glow.shadowOffset = .zero // LOCAL-TUNER
        return glow // LOCAL-TUNER
    } // LOCAL-TUNER
    static var sentTextStyle: ChatSentTextStyle { Tuner.value("Chat v2 Color/Sent text", default: ChatSentTextStyle.vivid) } // LOCAL-TUNER
    /// How much of the accent the tinted sent text takes. // LOCAL-TUNER
    static var sentTextTint: Double { Tuner.value("Chat v2 Color/Sent text tint", default: 0.175, in: 0...1, unit: .percent) } // LOCAL-TUNER
    /// The received bubble's fill.
    static var receivedFill: UIColor { UIColor(Tuner.value("Chat v2 Color/Received bubble", default: Color(r: 35, g: 35, b: 37))) } // LOCAL-TUNER
    /// Text on a received bubble.
    static let receivedText = UIColor.white
    /// Secondary text in the transcript: captions, the money card's labels, a resting reaction count.
    static let secondaryText = UIColor(Color(r: 235, g: 235, b: 245).opacity(0.6))
    /// The tint under a reaction the viewer added.
    static var accentTint: UIColor { UIColor(accent.color.opacity(0.16)) } // LOCAL-TUNER
    /// The ring around a reaction the viewer added.
    static var accentRing: UIColor { UIColor(accent.color.opacity(0.5)) } // LOCAL-TUNER
    /// The accent itself, for text and glyphs.
    static var accentColor: UIColor { UIColor(accent.color) } // LOCAL-TUNER

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
    static var authorNameSize: CGFloat { Tuner.value("Chat v2 Group/Name size", default: 12, in: 10...17, unit: .points) } // LOCAL-TUNER
    static var authorNameWeightChoice: ChatTextWeight { Tuner.value("Chat v2 Group/Name weight", default: ChatTextWeight.regular) } // LOCAL-TUNER
    static var authorNameWeight: UIFont.Weight { authorNameWeightChoice.weight } // LOCAL-TUNER

    // MARK: - Avatars

    /// A hairline ring around avatars, so a dark photo still reads as a circle. // LOCAL-TUNER
    static var avatarStrokeWidth: CGFloat { Tuner.value("Chat v2 Avatar/Stroke width", default: 1, in: 0...3, unit: .points) } // LOCAL-TUNER
    static var avatarStrokeOpacity: CGFloat { Tuner.value("Chat v2 Avatar/Stroke opacity", default: 0.05, in: 0...1, unit: .percent) } // LOCAL-TUNER
    /// The avatar beside a group author's first bubble. // LOCAL-TUNER
    static var authorAvatarSize: CGFloat { Tuner.value("Chat v2 Avatar/In-chat size", default: 28, in: 16...44, unit: .points) } // LOCAL-TUNER

    // MARK: - Swipe to reply

    static var replyIconSize: CGFloat { Tuner.value("Chat v2 Reply/Icon size", default: 24, in: 10...32, unit: .points) } // LOCAL-TUNER
    static var replyIconColor: Color { Tuner.value("Chat v2 Reply/Icon color", default: Color.white.opacity(0.4)) } // LOCAL-TUNER

    // MARK: - Mentions

    static var mentionStyle: ChatMentionStyle { Tuner.value("Chat v2 Mentions/Style", default: ChatMentionStyle.pill) } // LOCAL-TUNER
    static var mentionPillFill: Color { Tuner.value("Chat v2 Mentions/Pill fill", default: Color.white.opacity(0.14)) } // LOCAL-TUNER
    static var mentionPillFillSent: Color { Tuner.value("Chat v2 Mentions/Pill fill on sent", default: Color.white.opacity(0.14)) } // LOCAL-TUNER
    static var mentionPaddingX: CGFloat { Tuner.value("Chat v2 Mentions/Padding X", default: 5.75, in: 0...14, unit: .points) } // LOCAL-TUNER
    static var mentionPaddingY: CGFloat { Tuner.value("Chat v2 Mentions/Padding Y", default: 0, in: -2...8, unit: .points) } // LOCAL-TUNER
    static var mentionGap: CGFloat { Tuner.value("Chat v2 Mentions/Gap to words", default: 0, in: 0...10, unit: .points) } // LOCAL-TUNER
    static var mentionRadius: CGFloat { Tuner.value("Chat v2 Mentions/Corner radius", default: 7, in: 0...16, unit: .points) } // LOCAL-TUNER
    static var mentionCapsule: Bool { Tuner.value("Chat v2 Mentions/Capsule", default: true) } // LOCAL-TUNER
    static var mentionSize: CGFloat { Tuner.value("Chat v2 Mentions/Text size", default: 12.5, in: 10...22, unit: .points) } // LOCAL-TUNER
    static var mentionBaselineNudge: CGFloat { Tuner.value("Chat v2 Mentions/Baseline nudge", default: 0.5, in: -4...4, unit: .points) } // LOCAL-TUNER
    static var mentionWeight: ChatTextWeight { Tuner.value("Chat v2 Mentions/Weight", default: ChatTextWeight.semibold) } // LOCAL-TUNER
    static var mentionColorMode: ChatMentionColor { Tuner.value("Chat v2 Mentions/Text color", default: ChatMentionColor.custom) } // LOCAL-TUNER
    static var mentionCustomColor: Color { Tuner.value("Chat v2 Mentions/Custom color", default: Color.white.opacity(0.77)) } // LOCAL-TUNER
    static var mentionUnderline: Bool { Tuner.value("Chat v2 Mentions/Underline", default: false) } // LOCAL-TUNER
    /// A mention's text colour on a sender's bubble, or nil to keep the body's. // LOCAL-TUNER
    static func mentionText(isFromSelf: Bool) -> UIColor? { // LOCAL-TUNER
        switch mentionColorMode { // LOCAL-TUNER
        case .inherit: nil // LOCAL-TUNER
        case .accent: isFromSelf ? text(isFromSelf: true) : accentColor // LOCAL-TUNER
        case .vivid: vividAccent // LOCAL-TUNER
        case .custom: UIColor(mentionCustomColor) // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER

    // MARK: - Spacing

    /// Between two bubbles of one sender's run.
    static var runGap: CGFloat { Tuner.value("Chat v2 Spacing/Within a run", default: 4, in: 0...12, unit: .points) } // LOCAL-TUNER
    /// Between two messages of one sender that the grouping window broke apart, and around a date.
    static var momentGap: CGFloat { Tuner.value("Chat v2 Spacing/Same sender, new moment", default: 10, in: 0...24, unit: .points) } // LOCAL-TUNER
    /// Between two speakers.
    static var speakerGap: CGFloat { Tuner.value("Chat v2 Spacing/Speaker change", default: 16, in: 0...32, unit: .points) } // LOCAL-TUNER
    /// The transcript's side margin.
    static var rowInset: CGFloat { Tuner.value("Chat v2 Spacing/Side margin", default: 16, in: 8...24, unit: .points) } // LOCAL-TUNER

    // MARK: - Money card

    /// The money card's fill: neutral, so money reads the same under any accent.
    static var cardFill: UIColor { UIColor(Tuner.value("Chat v2 Money/Card fill", default: Color(r: 28, g: 28, b: 30))) } // LOCAL-TUNER
    static var cardRadius: CGFloat { Tuner.value("Chat v2 Money/Radius", default: 22, in: 8...32, unit: .points) } // LOCAL-TUNER
    static var cardWidth: CGFloat { Tuner.value("Chat v2 Money/Width", default: 240, in: 180...320, unit: .points) } // LOCAL-TUNER
    static var cardPaddingX: CGFloat { Tuner.value("Chat v2 Money/Padding X", default: 16, in: 8...28, unit: .points) } // LOCAL-TUNER
    static var cardPaddingTop: CGFloat { Tuner.value("Chat v2 Money/Padding top", default: 14, in: 4...28, unit: .points) } // LOCAL-TUNER
    static var cardPaddingBottom: CGFloat { Tuner.value("Chat v2 Money/Padding bottom", default: 22, in: 4...36, unit: .points) } // LOCAL-TUNER
    /// Between the card's header and its caption.
    static var cardHeaderGap: CGFloat { Tuner.value("Chat v2 Money/Header gap", default: 14, in: 0...32, unit: .points) } // LOCAL-TUNER
    /// The token badge in the header.
    static var cardBadgeSize: CGFloat { Tuner.value("Chat v2 Money/Badge size", default: 20, in: 12...32, unit: .points) } // LOCAL-TUNER
    static var cardLabelSize: CGFloat { Tuner.value("Chat v2 Money/Label size", default: 13, in: 10...17, unit: .points) } // LOCAL-TUNER
    static var cardAmountSize: CGFloat { Tuner.value("Chat v2 Money/Amount size", default: 34, in: 24...48, unit: .points) } // LOCAL-TUNER
    static var cardFlagSize: CGFloat { Tuner.value("Chat v2 Money/Flag size", default: 30, in: 20...40, unit: .points) } // LOCAL-TUNER
    /// The fill behind the cash badge's dollar glyph.
    static var cashBadgeFill: UIColor { UIColor(Tuner.value("Chat v2 Money/Cash green", default: Color(r: 48, g: 209, b: 88))) } // LOCAL-TUNER

    // MARK: - Reactions

    static var pillHeight: CGFloat { Tuner.value("Chat v2 Reactions/Height", default: 32, in: 20...36, unit: .points) } // LOCAL-TUNER
    static var pillLeadingPadding: CGFloat { Tuner.value("Chat v2 Reactions/Padding leading", default: 10, in: 2...16, unit: .points) } // LOCAL-TUNER
    static var pillTrailingPadding: CGFloat { Tuner.value("Chat v2 Reactions/Padding trailing", default: 2, in: 2...16, unit: .points) } // LOCAL-TUNER
    /// Between pills, and between the message and its pills.
    static var pillGap: CGFloat { Tuner.value("Chat v2 Reactions/Gap", default: 4, in: 0...12, unit: .points) } // LOCAL-TUNER
    /// Between a pill's emoji and its count.
    static var pillInnerGap: CGFloat { Tuner.value("Chat v2 Reactions/Emoji to count", default: 4, in: 0...12, unit: .points) } // LOCAL-TUNER
    static var pillCountRoom: Int { Tuner.value("Chat v2 Reactions/Count room (digits)", default: 2, in: 1...3) } // LOCAL-TUNER
    static var pillEmojiSize: CGFloat { Tuner.value("Chat v2 Reactions/Emoji size", default: 13, in: 11...22, unit: .points) } // LOCAL-TUNER
    static var pillCountSize: CGFloat { Tuner.value("Chat v2 Reactions/Count size", default: 13, in: 10...17, unit: .points) } // LOCAL-TUNER
    static var pillRingWidth: CGFloat { Tuner.value("Chat v2 Reactions/Ring width", default: 1.75, in: 0...3, unit: .points) } // LOCAL-TUNER
    /// A reaction nobody here added.
    static var pillFill: UIColor { UIColor(Tuner.value("Chat v2 Reactions/Fill", default: Color.white.opacity(0.09))) } // LOCAL-TUNER
    /// Whether the add-reaction button sits on a glass circle, as in v1.
    static var addReactionGlass: Bool { Tuner.value("Chat v2 Reactions/Add on glass", default: false) } // LOCAL-TUNER
    /// The add-reaction glyph.
    static var addReactionIconSize: CGFloat { Tuner.value("Chat v2 Reactions/Add icon size", default: 19.3, in: 12...24, unit: .points) } // LOCAL-TUNER

    // LOCAL-TUNER: reads every value once, so all of them register in the panel and the transcript can observe them.
    static func readAll() -> [Any] { // LOCAL-TUNER
        [ChatDateSeparatorCell.styled("Oct 20 15:40"), Color.backgroundMain, replyIconSize, replyIconColor, mentionStyle, mentionPillFill, mentionPillFillSent, mentionPaddingX, mentionPaddingY, mentionGap, mentionRadius, mentionCapsule, mentionSize, mentionBaselineNudge, mentionWeight, mentionColorMode, mentionCustomColor, mentionUnderline, avatarStrokeWidth, avatarStrokeOpacity, authorAvatarSize, authorNameSize, authorNameWeightChoice, bubbleRadius, joinedRadius, cornerStyleChoice, bubblePaddingX, bubblePaddingY, bodySize, bodyWeightChoice, bodyLineHeight, drawsHairline, maxWidthFraction, // LOCAL-TUNER
         accent, ChatAccent.custom.color, sentTextStyle, sentTextTint, sentOpacity, vividSaturation, vividBrightness, vividLift, vividInP3, sentGlowRadius, sentGlowOpacity, receivedFill, runGap, momentGap, speakerGap, rowInset, // LOCAL-TUNER
         cardFill, cardRadius, cardWidth, cardPaddingX, cardPaddingTop, cardPaddingBottom, cardHeaderGap, cardBadgeSize, cardLabelSize, cardAmountSize, cardFlagSize, cashBadgeFill, // LOCAL-TUNER
         pillHeight, pillLeadingPadding, pillTrailingPadding, pillGap, pillInnerGap, pillCountRoom, pillEmojiSize, pillCountSize, pillRingWidth, pillFill, addReactionGlass, addReactionIconSize] // LOCAL-TUNER
    } // LOCAL-TUNER
}

// LOCAL-TUNER: the choices behind the tuner's pickers. Baking keeps the picked value only.
nonisolated enum ChatAccent: String, TunableEnum, Sendable { // LOCAL-TUNER
    case ink, graphite, smoke, blue, sky, cyan, teal, mint, lime, yellow, amber, orange, person, coral, red, rose, pink, magenta, purple, violet, indigo, navy, forest, brown, sand, custom // LOCAL-TUNER
    var color: Color { // LOCAL-TUNER
        switch self { // LOCAL-TUNER
        case .ink: Self.hex(0xF2F2F5) // LOCAL-TUNER
        case .graphite: Self.hex(0x48484A) // LOCAL-TUNER
        case .smoke: Self.hex(0x8E8E93) // LOCAL-TUNER
        case .blue: Self.hex(0x0A84FF) // LOCAL-TUNER
        case .sky: Self.hex(0x5AC8FA) // LOCAL-TUNER
        case .cyan: Self.hex(0x64D2FF) // LOCAL-TUNER
        case .teal: Self.hex(0x30B0C7) // LOCAL-TUNER
        case .mint: Self.hex(0x63E6BE) // LOCAL-TUNER
        case .lime: Self.hex(0xA8E05F) // LOCAL-TUNER
        case .yellow: Self.hex(0xFFD60A) // LOCAL-TUNER
        case .amber: Self.hex(0xFFB340) // LOCAL-TUNER
        case .orange: Self.hex(0xFF9F0A) // LOCAL-TUNER
        case .person: Self.hex(0xE0723F) // LOCAL-TUNER
        case .coral: Self.hex(0xFF6B5A) // LOCAL-TUNER
        case .red: Self.hex(0xFF453A) // LOCAL-TUNER
        case .rose: Self.hex(0xFF375F) // LOCAL-TUNER
        case .pink: Self.hex(0xFF6FB5) // LOCAL-TUNER
        case .magenta: Self.hex(0xE040A0) // LOCAL-TUNER
        case .purple: Self.hex(0xBF5AF2) // LOCAL-TUNER
        case .violet: Self.hex(0x7457FF) // LOCAL-TUNER
        case .indigo: Self.hex(0x5E5CE6) // LOCAL-TUNER
        case .navy: Self.hex(0x2C4BD4) // LOCAL-TUNER
        case .forest: Self.hex(0x2E8B57) // LOCAL-TUNER
        case .brown: Self.hex(0xAC8E68) // LOCAL-TUNER
        case .sand: Self.hex(0xD8C3A5) // LOCAL-TUNER
        case .custom: Tuner.value("Chat v2 Color/Custom accent", default: Self.hex(0x0A84FF)) // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER
    /// Near-black on a light accent, white on a dark one, picked by the accent's luminance. // LOCAL-TUNER
    var onColor: Color { // LOCAL-TUNER
        let c = UIColor(color).cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0] // LOCAL-TUNER
        let lin = { (v: CGFloat) in v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) } // LOCAL-TUNER
        let luminance = 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]) // LOCAL-TUNER
        return luminance > 0.4 ? Self.hex(0x0B0B0C) : .white // LOCAL-TUNER
    } // LOCAL-TUNER
    private static func hex(_ value: Int) -> Color { // LOCAL-TUNER
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255) // LOCAL-TUNER
    } // LOCAL-TUNER
} // LOCAL-TUNER

nonisolated enum ChatSentTextStyle: String, TunableEnum, Sendable { // LOCAL-TUNER
    case white, tinted, vivid, auto // LOCAL-TUNER
} // LOCAL-TUNER

nonisolated enum ChatMentionStyle: String, TunableEnum, Sendable { case pill, plain } // LOCAL-TUNER
nonisolated enum ChatMentionColor: String, TunableEnum, Sendable { case inherit, accent, vivid, custom } // LOCAL-TUNER

nonisolated enum ChatCornerStyle: String, TunableEnum, Sendable { // LOCAL-TUNER
    case circular, continuous // LOCAL-TUNER
    var style: RoundedCornerStyle { self == .circular ? .circular : .continuous } // LOCAL-TUNER
} // LOCAL-TUNER

nonisolated enum ChatTextWeight: String, TunableEnum, Sendable { // LOCAL-TUNER
    case regular, medium, semibold // LOCAL-TUNER
    var weight: UIFont.Weight { // LOCAL-TUNER
        switch self { case .regular: .regular; case .medium: .medium; case .semibold: .semibold } // LOCAL-TUNER
    } // LOCAL-TUNER
} // LOCAL-TUNER

private extension UIColor { // LOCAL-TUNER
    func mixed(withWhite amount: CGFloat) -> UIColor { // LOCAL-TUNER
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0 // LOCAL-TUNER
        getRed(&r, green: &g, blue: &b, alpha: &a) // LOCAL-TUNER
        return UIColor(red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount, alpha: a) // LOCAL-TUNER
    } // LOCAL-TUNER
} // LOCAL-TUNER
#endif
