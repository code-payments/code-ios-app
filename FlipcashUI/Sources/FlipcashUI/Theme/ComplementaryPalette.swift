//
//  ComplementaryPalette.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import CryptoKit
import FlipcashCore

#if canImport(UIKit)
import UIKit
#endif

/// The colour a person is drawn in, derived from their user id.
///
/// A port of Android's `generateComplementaryColorPalette`
/// (`ui/components/.../utils/ComplementaryGradient.kt`), arithmetic for arithmetic: SHA-512 the id's
/// bytes, take the hue from the sum of the first three, wobble the brightness by the fourth, and
/// shift 20° for each further stop. Ported rather than re-derived because both apps show the same
/// conversations — a person who is teal on Android and amber here reads as two people.
///
/// Android's third stop carries a WCAG contrast correction that only the anonymous-avatar gradient
/// needs. Nothing here draws that gradient, so the correction is not ported; bring it over with the
/// stop if an avatar ever needs it.
///
/// Not memoized, where Android keeps a map. One SHA-512 over sixteen bytes is cheaper than the lock
/// a shared cache would need to be safe off the main actor.
public enum ComplementaryPalette {

    /// Which stop to take. Android names them by position; a quote uses the first for its rule and
    /// the second — the lighter of the two — for the author's name.
    public enum Stop {
        case start
        case middle
    }

    /// Fixed on Android: the id chooses the hue and a small brightness wobble, nothing else.
    private static let saturation = 0.75
    private static let baseBrightness = 0.85
    /// Degrees between one stop and the next.
    private static let hueShift = 20.0

    /// The person's colour, or the neutral secondary text colour when there is no id to derive one
    /// from — an original the local database has never seen has no author, let alone a colour.
    /// Android falls back the same way, to its `tertiary`.
    public static func color(_ stop: Stop, for id: UserID?) -> Color {
        guard let hsb = components(stop, for: id) else { return .textSecondary }
        return Color(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness)
    }

    #if canImport(UIKit)
    /// See ``color(_:for:)``. The transcript draws its quote panel in UIKit.
    public static func uiColor(_ stop: Stop, for id: UserID?) -> UIColor {
        guard let hsb = components(stop, for: id) else { return UIColor(Color.textSecondary) }
        return UIColor(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness, alpha: 1)
    }
    #endif

    /// The person's colour as text: the `.middle` stop, lightened until it reads on the dark surface.
    ///
    /// Some hues come out of the palette too dark to read as a name (`#553ED9` is 2.2:1). Blends the
    /// stop 15% toward white, in gamma sRGB, until it reaches 4.5:1 against a fixed `#262626` or
    /// ten steps have run. The surface is a constant rather than read from the theme so Android,
    /// which applies the identical rule, lands on the same colour. `.start` and `.middle` are left
    /// alone: the rule and Android's avatar gradient use them as they are.
    public static func nameColor(for id: UserID?) -> Color {
        guard let rgb = nameRGB(for: id) else { return .textSecondary }
        return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }

    #if canImport(UIKit)
    /// See ``nameColor(for:)``. The transcript draws its quote panel in UIKit.
    public static func uiNameColor(for id: UserID?) -> UIColor {
        guard let rgb = nameRGB(for: id) else { return UIColor(Color.textSecondary) }
        return UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }
    #endif

    /// The surface names are corrected against, sRGB `#262626`.
    static let nameSurface = 0x26 / 255.0
    static let nameMinimumContrast = 4.5
    private static let nameMaxSteps = 10
    private static let nameLift = 0.15

    static func nameRGB(for id: UserID?) -> (r: Double, g: Double, b: Double)? {
        guard let hsb = components(.middle, for: id) else { return nil }
        var rgb = rgb(hue: hsb.hue * 360, saturation: hsb.saturation, value: hsb.brightness)
        let surface = relativeLuminance(nameSurface, nameSurface, nameSurface)
        var steps = 0
        while contrast(relativeLuminance(rgb.r, rgb.g, rgb.b), surface) < nameMinimumContrast, steps < nameMaxSteps {
            rgb = (rgb.r + (1 - rgb.r) * nameLift, rgb.g + (1 - rgb.g) * nameLift, rgb.b + (1 - rgb.b) * nameLift)
            steps += 1
        }
        return rgb
    }

    /// WCAG contrast ratio of two relative luminances.
    static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func relativeLuminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static func rgb(hue: Double, saturation: Double, value: Double) -> (r: Double, g: Double, b: Double) {
        let c = value * saturation
        let h = hue / 60
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = value - c
        let (r, g, b): (Double, Double, Double)
        switch Int(h) % 6 {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    /// Hue normalized to 0...1 for both colour types, which take it that way where Compose takes
    /// degrees. The saturation and brightness are Android's numbers untouched.
    private static func components(
        _ stop: Stop,
        for id: UserID?
    ) -> (hue: Double, saturation: Double, brightness: Double)? {
        guard let id else { return nil }
        let digest = Array(SHA512.hash(data: withUnsafeBytes(of: id.uuid) { Data($0) }))
        let hue = Double((Int(digest[0]) + Int(digest[1]) + Int(digest[2])) % 360)
        let variation = Double(Int(digest[3]) % 10) / 100
        switch stop {
        case .start:
            return (hue / 360, saturation, baseBrightness - variation)
        case .middle:
            return ((hue + hueShift).truncatingRemainder(dividingBy: 360) / 360,
                    saturation * 0.95,
                    baseBrightness)
        }
    }
}
