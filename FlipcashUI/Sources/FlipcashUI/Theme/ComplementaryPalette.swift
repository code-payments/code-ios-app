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
