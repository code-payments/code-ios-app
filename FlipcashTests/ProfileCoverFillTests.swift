//
//  ProfileCoverFillTests.swift
//  FlipcashTests
//

import SwiftUI
import Testing
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("ProfileCoverFill")
struct ProfileCoverFillTests {

    @Test("A valid hex gives the parsed colour")
    func validHexIsParsed() {
        let color = ProfileCoverFill.color(for: TipCardCustomization(colorHex: "#19191A"))

        #expect(color == Color(hex: "#19191A"))
    }

    @Test("An unparsable hex gives the default")
    func invalidHexFallsBack() {
        let color = ProfileCoverFill.color(for: TipCardCustomization(colorHex: "not-a-colour"))

        #expect(color == ProfileCoverFill.fallback)
    }

    @Test("No customization gives the default")
    func nilFallsBack() {
        #expect(ProfileCoverFill.color(for: nil) == ProfileCoverFill.fallback)
    }
}
