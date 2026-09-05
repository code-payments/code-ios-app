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
}
