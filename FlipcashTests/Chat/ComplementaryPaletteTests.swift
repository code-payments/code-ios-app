//
//  ComplementaryPaletteTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import SwiftUI
import UIKit
import FlipcashCore
@testable import FlipcashUI

/// Pins the port of Android's `generateComplementaryColorPalette` to exact colours.
///
/// The expected values are not read back from this implementation — they were computed
/// independently from Android's arithmetic (SHA-512 the id's bytes, hue from the sum of the first
/// three, brightness wobble from the fourth, 20° to the next stop). That is the whole point of the
/// suite: it fails if the Swift side drifts from the Kotlin side, which is the one thing a person
/// looking at both apps would notice.
@MainActor
@Suite("ComplementaryPalette")
struct ComplementaryPaletteTests {

    private let ada = UUID(uuidString: "8B3D4E1A-0000-4000-8000-000000000007")!
    private let zeroes = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    @Test("A user id lands on Android's colours")
    func matchesAndroidArithmetic() {
        #expect(ComplementaryPalette.color(.start, for: ada).hexString == "#D69336")
        #expect(ComplementaryPalette.color(.middle, for: ada).hexString == "#D9CC3E")
        #expect(ComplementaryPalette.color(.start, for: zeroes).hexString == "#D936CB")
        #expect(ComplementaryPalette.color(.middle, for: zeroes).hexString == "#D93E98")
    }

    @Test("The same person is the same colour every time")
    func isStable() {
        // Swift's own `hashValue` is seeded per process, so a palette built on it would repaint
        // every quote on the next launch. This is the assertion that catches that mistake.
        #expect(
            ComplementaryPalette.color(.start, for: ada).hexString
                == ComplementaryPalette.color(.start, for: ada).hexString
        )
    }

    @Test("Two people are two colours")
    func separatesPeople() {
        #expect(
            ComplementaryPalette.color(.start, for: ada).hexString
                != ComplementaryPalette.color(.start, for: zeroes).hexString
        )
    }

    @Test("An author we have no id for falls back to the neutral")
    func fallsBackWithoutAnID() {
        #expect(ComplementaryPalette.color(.start, for: nil).hexString == Color.textSecondary.hexString)
        #expect(ComplementaryPalette.color(.middle, for: nil).hexString == Color.textSecondary.hexString)
    }

    @Test("The UIKit form agrees with the SwiftUI one")
    func uiColorAgrees() {
        #expect(
            Color(ComplementaryPalette.uiColor(.start, for: ada)).hexString
                == ComplementaryPalette.color(.start, for: ada).hexString
        )
    }

    // MARK: - Name colour

    /// (user id, `.middle` stop, name colour) shared with Android's identical rule.
    private static let nameVectors: [(id: String, middle: String, name: String)] = [
        ("00000000-0000-0000-0000-000000000001", "#D93E7C", "#E374A0"),
        ("6f1c2a9e-3b7d-4e21-9a55-0c4d8e7f1b23", "#3ED9BC", "#3ED9BC"),
        ("a3e5b8c1-77d2-4f90-8b1e-2d6c9f0a4e57", "#D9C73E", "#D9C73E"),
        ("deadbeef-0000-4000-8000-000000000000", "#3E91D9", "#5BA1DE"),
        ("6513270e-269e-4d37-b2a7-4de452e6b438", "#D13ED9", "#D85BDE"),
        ("73ab4876-7734-47c1-87fd-e805ec99108d", "#553ED9", "#9789E8"),
    ]

    private func channels(_ hex: String) -> [Int] {
        let value = Int(hex.dropFirst(), radix: 16)!
        return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
    }

    private func matches(_ actual: String, _ expected: String) -> Bool {
        zip(channels(actual), channels(expected)).allSatisfy { abs($0 - $1) <= 1 }
    }

    @Test("The middle stop matches the shared vectors")
    func middleMatchesVectors() {
        for vector in Self.nameVectors {
            let actual = ComplementaryPalette.color(.middle, for: UUID(uuidString: vector.id)!).hexString
            #expect(matches(actual, vector.middle), "\(vector.id): \(actual) vs \(vector.middle)")
        }
    }

    @Test("The name colour matches the shared vectors")
    func nameMatchesVectors() {
        for vector in Self.nameVectors {
            let id = UUID(uuidString: vector.id)!
            let actual = ComplementaryPalette.nameColor(for: id).hexString
            #expect(matches(actual, vector.name), "\(vector.id): \(actual) vs \(vector.name)")
            #expect(matches(Color(ComplementaryPalette.uiNameColor(for: id)).hexString, vector.name))
        }
    }

    @Test("Every name colour reads at 4.5:1 on #262626")
    func nameContrast() {
        let surface = ComplementaryPalette.relativeLuminance(0x26 / 255.0, 0x26 / 255.0, 0x26 / 255.0)
        for _ in 0..<500 {
            let rgb = ComplementaryPalette.nameRGB(for: UUID())!
            let ratio = ComplementaryPalette.contrast(ComplementaryPalette.relativeLuminance(rgb.r, rgb.g, rgb.b), surface)
            #expect(ratio >= 4.5)
        }
    }

    @Test("No id falls back to the secondary text colour")
    func nameFallback() {
        #expect(ComplementaryPalette.nameColor(for: nil).hexString == Color.textSecondary.hexString)
    }

    // MARK: - Adaptive name colour

    /// (user id, light name colour), the same ids as ``nameVectors``. Computed independently: the
    /// `.middle` stop scaled by 0.85 per step until it holds 4.5:1 on `#CFCFCF`.
    private static let lightNameVectors: [(id: String, light: String)] = [
        ("00000000-0000-0000-0000-000000000001", "#9D2D5A"),
        ("6f1c2a9e-3b7d-4e21-9a55-0c4d8e7f1b23", "#1C6054"),
        ("a3e5b8c1-77d2-4f90-8b1e-2d6c9f0a4e57", "#60581C"),
        ("deadbeef-0000-4000-8000-000000000000", "#265985"),
        ("6513270e-269e-4d37-b2a7-4de452e6b438", "#802685"),
        ("73ab4876-7734-47c1-87fd-e805ec99108d", "#4935B8"),
    ]

    private static let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
    private static let lightTraits = UITraitCollection(userInterfaceStyle: .light)

    private func rgba(_ color: UIColor, in traits: UITraitCollection) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    private func hex(_ color: UIColor, in traits: UITraitCollection) -> String {
        let c = rgba(color, in: traits).map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c[0], c[1], c[2])
    }

    private func nearlyEqual(_ a: [CGFloat], _ b: [CGFloat]) -> Bool {
        zip(a, b).allSatisfy { abs($0 - $1) < 1e-6 }
    }

    private func ratio(_ rgb: (r: Double, g: Double, b: Double), onGrey grey: Double) -> Double {
        ComplementaryPalette.contrast(
            ComplementaryPalette.relativeLuminance(rgb.r, rgb.g, rgb.b),
            ComplementaryPalette.relativeLuminance(grey, grey, grey)
        )
    }

    @Test("In dark the adaptive name is today's name colour")
    func adaptiveNameKeepsDark() {
        let ids = Self.nameVectors.map { UUID(uuidString: $0.id)! } + (0..<200).map { _ in UUID() }
        for id in ids {
            // UIKit: exactly the colour the quote panel drew before light mode.
            #expect(
                rgba(ComplementaryPalette.uiAdaptiveNameColor(for: id), in: Self.darkTraits)
                    == rgba(ComplementaryPalette.uiNameColor(for: id), in: Self.darkTraits)
            )
            #expect(nearlyEqual(
                rgba(UIColor(ComplementaryPalette.adaptiveNameColor(for: id)), in: Self.darkTraits),
                rgba(UIColor(ComplementaryPalette.nameColor(for: id)), in: Self.darkTraits)
            ))
        }
        for vector in Self.nameVectors {
            let actual = ComplementaryPalette.adaptiveNameColor(for: UUID(uuidString: vector.id)!).hexString
            #expect(matches(actual, vector.name), "\(vector.id): \(actual) vs \(vector.name)")
        }
    }

    @Test("In light the adaptive name matches the light vectors")
    func adaptiveNameMatchesLightVectors() {
        for vector in Self.lightNameVectors {
            let id = UUID(uuidString: vector.id)!
            let ui = hex(ComplementaryPalette.uiAdaptiveNameColor(for: id), in: Self.lightTraits)
            let swiftUI = hex(UIColor(ComplementaryPalette.adaptiveNameColor(for: id)), in: Self.lightTraits)
            #expect(matches(ui, vector.light), "\(vector.id): \(ui) vs \(vector.light)")
            #expect(matches(swiftUI, vector.light), "\(vector.id): \(swiftUI) vs \(vector.light)")
        }
    }

    @Test("Every hue's light name reads at 4.5:1 on the light reference ground")
    func lightNameContrastEveryHue() {
        // The `.middle` stop from Android's arithmetic: any whole-degree hue, saturation 0.75 × 0.95,
        // brightness 0.85. Checked on the reference grey and on the darkest ground it stands in for,
        // a sent quote's `#BFD0F6`.
        let darkestGround = ComplementaryPalette.relativeLuminance(0xBF / 255.0, 0xD0 / 255.0, 0xF6 / 255.0)
        for hue in 0..<360 {
            let rgb = ComplementaryPalette.lightNameRGB(hue: Double(hue) / 360, saturation: 0.75 * 0.95, brightness: 0.85)
            #expect(ratio(rgb, onGrey: 0xCF / 255.0) >= 4.5, "hue \(hue)")
            let onDarkest = ComplementaryPalette.contrast(
                ComplementaryPalette.relativeLuminance(rgb.r, rgb.g, rgb.b),
                darkestGround
            )
            #expect(onDarkest >= 4.5, "hue \(hue) on #BFD0F6")
        }
    }

    @Test("A person's light name is their colour, darkened")
    func lightNameKeepsHue() {
        for _ in 0..<200 {
            let id = UUID()
            let light = ComplementaryPalette.uiAdaptiveNameColor(for: id).resolvedColor(with: Self.lightTraits)
            let middle = ComplementaryPalette.uiColor(.middle, for: id)
            var lightHue: CGFloat = 0, lightSaturation: CGFloat = 0, middleHue: CGFloat = 0, middleSaturation: CGFloat = 0
            light.getHue(&lightHue, saturation: &lightSaturation, brightness: nil, alpha: nil)
            middle.getHue(&middleHue, saturation: &middleSaturation, brightness: nil, alpha: nil)
            #expect(abs(lightHue - middleHue) < 1e-6)
            #expect(abs(lightSaturation - middleSaturation) < 1e-6)
            #expect(ratio(ComplementaryPalette.lightNameRGB(for: id)!, onGrey: 0xCF / 255.0) >= 4.5)
        }
    }

    @Test("No id falls back to the secondary text colour in both appearances")
    func adaptiveNameFallback() {
        let secondary = UIColor(Color.textSecondary)
        for traits in [Self.darkTraits, Self.lightTraits] {
            #expect(nearlyEqual(rgba(ComplementaryPalette.uiAdaptiveNameColor(for: nil), in: traits), rgba(secondary, in: traits)))
            #expect(nearlyEqual(rgba(UIColor(ComplementaryPalette.adaptiveNameColor(for: nil)), in: traits), rgba(secondary, in: traits)))
        }
    }
}
