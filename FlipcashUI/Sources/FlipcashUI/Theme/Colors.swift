//
//  Color.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashCore

extension ShapeStyle where Self == Color {
    public static var textMain: Color                    { Palette.textMain }
    public static var textSecondary: Color               { Palette.textSecondary }
    /// ~30% white in dark and a pale grey in light — dimmer than `textSecondary` in both. Used for
    /// placeholder amounts (e.g. the Convert/Get "$0" before entry).
    public static var textTertiary: Color                { Palette.textTertiary }
    public static var textAction: Color                  { Palette.textAction }
    public static var textActionDisabled: Color          { Palette.textActionDisabled }
    public static var textError: Color                   { Palette.textError }
    public static var textSuccess: Color                 { Palette.textSuccess }
    public static var textWarning: Color                 { Palette.textWarning }
    public static var warning: Color                     { Palette.warning }
    /// The ground `warning` sits on when it labels a state rather than raising an alarm — amber at
    /// about a tenth of its strength over ``backgroundMain``, baked flat the way the sentiment pair
    /// secondaries are. Only true against the main background; it is not a general wash.
    public static var warningSecondary: Color            { Palette.warningSecondary }

    public static var action: Color                      { Palette.action }
    public static var actionDisabled: Color              { Palette.actionDisabled }
    /// The secondary button's fill, under `.subtle` and a tray's secondary action: ``fillControl``.
    public static var actionSecondary: Color             { Palette.fillControl }
    public static var textActionSecondaryDisabled: Color { Palette.textActionSecondaryDisabled }

    public static var bannerError: Color                 { Color(r: 188, g: 52,  b: 52) }
    public static var bannerInfo: Color                  { Color("backgroundSecondary") }
    public static var bannerSuccess: Color               { Color("backgroundSecondary") }

    public static var backgroundMain: Color              { Color("background") }
    public static var backgroundSecondary: Color         { Color("backgroundSecondary") }
    public static var backgroundRow: Color               { Palette.backgroundRow }
    public static var rowSeparator: Color                { Palette.rowSeparator }
    /// `#323234` dark, `#E5E5EA` light — the flat fill behind a profile's cover banner when the profile has no cover picture.
    public static var coverPlaceholder: Color            { Palette.coverPlaceholder }

    /// The faint fill for a raised panel, placeholder or chip that sits on the page or a row.
    public static var fillSubtle: Color                  { Palette.fillSubtle }
    /// The fill behind a control or chip that needs more weight than ``fillSubtle``.
    public static var fillControl: Color                 { Palette.fillControl }
    /// The fill that marks the selected item among its siblings.
    public static var fillSelected: Color                { Palette.fillSelected }
    /// The dim laid over content behind a presented object, black in both appearances.
    public static var scrim: Color                       { Palette.scrim }

    public static var unreadIndicator: Color             { Palette.unreadIndicator }
    /// The ground `unreadIndicator` sits on in the chat row's Unread/Read swipe — the blue at a
    /// tenth of its strength over ``backgroundMain``, baked flat the way ``warningSecondary`` is.
    /// Only true against the main background; it is not a general wash.
    public static var unreadIndicatorSecondary: Color    { Color(r: 24,  g: 36,  b: 49)  }
    /// `#0A84FF` dark, `#007AFF` light — the badge/focus token, used by the jump-to-bottom unread badge. Same value as `unreadIndicator`, named for its Figma token.
    public static var badgeFocus: Color                  { Palette.unreadIndicator }

    public static var checkmarkBackground: Color         { Palette.checkmarkBackground }

    /// `#FFC828` dark, `#8F6200` light — a paid reaction's amount and border; its fill is this at 10%.
    public static var reactionBoost: Color               { Palette.reactionBoost }

    /// `#1AC86A` — the shared success fill (switch tracks, bubbles, filled icons) in both appearances,
    /// the same green Android uses. Success text uses `textSuccess` (`#73EAA4` dark, `#0E7842` light).
    /// Backed by the `success` asset.
    public static var success: Color                     { Color("success") }
}

extension Color {
    public struct Sentiment {
        public static let positive          = Color(light: Color(r: 14,  g: 120, b: 66),  dark: Color(r: 49,  g: 156, b: 88))
        public static let positiveSecondary = Color(light: Color(r: 227, g: 239, b: 232), dark: Color(r: 17,  g: 53,  b: 34))
        public static let negative          = Color(light: Color(r: 204, g: 36,  b: 36),  dark: Color(r: 228, g: 42,  b: 42))
        public static let negativeSecondary = Color(light: Color(r: 250, g: 233, b: 233), dark: Color(r: 60,  g: 37,  b: 37))
        public static let neutral           = Color.textSecondary
    }
}

/// The appearance-following tokens, built once so every read returns the same colour.
private enum Palette {
    static let textMain                    = Color(light: .black,                     dark: .white)
    static let textSecondary               = Color(light: Color(r: 96, g: 96, b: 101), dark: Color(r: 123, g: 123, b: 123))
    static let textTertiary                = Color(light: Color(r: 170, g: 170, b: 174), dark: Color(r: 78,  g: 78,  b: 78))
    static let textAction                  = Color(light: .white,                     dark: .black)
    static let textActionDisabled          = Color(light: Color(r: 170, g: 170, b: 174), dark: Color(r: 78,  g: 78,  b: 78))
    static let textError                   = Color(light: Color(r: 201, g: 42,  b: 42),  dark: Color(r: 255, g: 131, b: 131))
    static let textSuccess                 = Color(light: Color(r: 14,  g: 120, b: 66),  dark: Color(r: 115, g: 234, b: 164))
    static let textWarning                 = Color(light: Color(r: 130, g: 99,  b: 0),   dark: Color(r: 255, g: 243, b: 131))
    static let warning                     = Color(light: Color(r: 194, g: 106, b: 0),   dark: Color(r: 255, g: 169, b: 57))
    static let warningSecondary            = Color(light: Color(r: 248, g: 237, b: 224), dark: Color(r: 48,  g: 39,  b: 29))

    static let action                      = Color(light: .black,                     dark: .white)
    static let actionDisabled              = Color(light: Color(r: 239, g: 239, b: 240), dark: Color(r: 30,  g: 30,  b: 30))
    static let textActionSecondaryDisabled = Color(light: Color(r: 247, g: 247, b: 248), dark: Color(r: 24,  g: 24,  b: 24))

    static let backgroundRow               = Color(light: Color(r: 116, g: 116, b: 128, o: 0.08), dark: .white.opacity(0.05))
    static let rowSeparator                = Color(light: Color(r: 60,  g: 60,  b: 67,  o: 0.29), dark: .white.opacity(0.1))
    static let coverPlaceholder            = Color(light: Color(r: 229, g: 229, b: 234), dark: Color(r: 50,  g: 50,  b: 52))

    static let fillSubtle                  = Color(light: Color(r: 118, g: 118, b: 128, o: 0.12), dark: .white.opacity(0.08))
    static let fillControl                 = Color(light: Color(r: 120, g: 120, b: 128, o: 0.16), dark: .white.opacity(0.1))
    static let fillSelected                = Color(light: Color(r: 120, g: 120, b: 128, o: 0.2),  dark: .white.opacity(0.2))
    static let scrim                       = Color(light: .black.opacity(0.3),        dark: .black.opacity(0.6))

    static let unreadIndicator             = Color(light: Color(r: 0,   g: 122, b: 255), dark: Color(r: 10,  g: 132, b: 255))
    static let checkmarkBackground         = Color(light: .black,                     dark: .white)
    static let reactionBoost               = Color(light: Color(r: 143, g: 98,  b: 0),   dark: Color(r: 255, g: 200, b: 40))
}

// MARK: - Color -

extension Color {
    public init(r: Double, g: Double, b: Double, o: Double = 1.0) {
        self.init(
            red:     r / 255.0,
            green:   g / 255.0,
            blue:    b / 255.0,
            opacity: o
        )
    }

    /// Creates a colour that resolves to `dark` in the dark appearance and to `light` in every other
    /// appearance, in SwiftUI views and UIKit trait collections alike.
    public init(light: Color, dark: Color) {
        let light = UIColor(light)
        let dark = UIColor(dark)
        // UIKit resolves dynamic colours on whatever thread renders, so the provider must not
        // inherit the module's main-actor isolation.
        self.init(uiColor: UIColor { @Sendable traits in
            (traits.userInterfaceStyle == .dark ? dark : light).resolvedColor(with: traits)
        })
    }

    /// Initialize a Color from a hex string in `#RRGGBB` format.
    /// Returns `nil` if the string is not a valid hex color.
    public init?(hex: String) {
        var hexString = hex
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6, let rgb = UInt64(hexString, radix: 16) else {
            return nil
        }

        self.init(
            r: Double((rgb >> 16) & 0xFF),
            g: Double((rgb >>  8) & 0xFF),
            b: Double( rgb        & 0xFF)
        )
    }

    /// Renders the Color as a `#RRGGBB` hex string, always as its dark-appearance value so an
    /// exported or serialised colour never depends on the appearance the device is in. Rounds
    /// component products to keep `Color(hex: c.hexString)?.hexString == c.hexString` — truncating
    /// leaks a 1-bit drift on the round-trip because `n/255 * 255` is just under `n` in floating point.
    public var hexString: String {
        let uiColor = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var red:   CGFloat = 0
        var green: CGFloat = 0
        var blue:  CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let r = Int((red   * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue  * 255).rounded())
        let rgb = r << 16 | g << 8 | b
        return String(format: "#%06X", rgb)
    }
}
