//
//  ComplementaryPaletteTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import SwiftUI
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
}
