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
    public static var textMain: Color                    { Color.white }
    public static var textSecondary: Color               { Color(r: 123, g: 123, b: 123) }
    public static var textAction: Color                  { Color.black }
    public static var textActionDisabled: Color          { Color(r: 78,  g: 78,  b: 78) }
    public static var textError: Color                   { Color(r: 255, g: 131, b: 131) }
    public static var textSuccess: Color                 { Color(r: 73 , g: 213, b: 23) }
    public static var textWarning: Color                 { Color(r: 255, g: 243, b: 131) }

    public static var action: Color                      { Color.white }
    public static var actionDisabled: Color              { Color(r: 30,  g: 30,  b: 30) }
    public static var textActionSecondaryDisabled: Color { Color(r: 24,  g: 24,  b: 24) }

    public static var bannerError: Color                 { Color(r: 188, g: 52,  b: 52) }
    public static var bannerInfo: Color                  { Color(r: 26,  g: 49,  b: 37) }
    public static var bannerSuccess: Color               { Color("backgroundSecondary") }

    public static var backgroundMain: Color              { Color("background") }
    public static var backgroundSecondary: Color         { Color("backgroundSecondary") }
    public static var backgroundRow: Color               { Color.white.opacity(0.05) }
    public static var rowSeparator: Color                { Color.white.opacity(0.1) }

    public static var checkmarkBackground: Color         { Color.white }
}

extension Color {
    public struct Sentiment {
        public static let positive          = Color(r: 49,  g: 156, b: 88)
        public static let positiveSecondary = Color(r: 17,  g: 53,  b: 34)
        public static let negative          = Color(r: 228, g: 42,  b: 42)
        public static let negativeSecondary = Color(r: 60,  g: 37,  b: 37)
        public static let neutral           = Color.textSecondary
    }
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

    /// Renders the Color as a `#RRGGBB` hex string. Resolves through `UIColor`
    /// so SwiftUI's dynamic colors flatten to their current trait collection's
    /// concrete values. Rounds component products to keep
    /// `Color(hex: c.hexString)?.hexString == c.hexString` — truncating leaks
    /// a 1-bit drift on the round-trip because `n/255 * 255` is just under `n`
    /// in floating point.
    public var hexString: String {
        let uiColor = UIColor(self)
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
