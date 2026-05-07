//
//  BillDesignerColorsTests.swift
//  FlipcashTests
//
//  Pin the bill designer's hue derivation: a single random hue must
//  expand into three HSB-fixed colors that round-trip cleanly through
//  the hex pipeline used by the launch payload.
//

import Testing
import SwiftUI
import UIKit
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Bill Designer color derivation")
struct BillDesignerColorsTests {

    private static let lightSaturation: CGFloat = 0.53
    private static let lightBrightness: CGFloat = 1.00
    private static let midSaturation:   CGFloat = 1.00
    private static let midBrightness:   CGFloat = 0.71
    private static let darkSaturation:  CGFloat = 1.00
    private static let darkBrightness:  CGFloat = 0.23

    @Test(
        "deriveColors produces the spec's HSB triple for any hue",
        arguments: [0.0, 0.08, 0.34, 0.5, 0.6, 0.75, 0.95] as [CGFloat]
    )
    func derivesExpectedHSB(hue: CGFloat) throws {
        let result = ColorEditorControl.deriveColors(fromHue: hue)

        try #require(result.count == 3)

        let expected: [(s: CGFloat, b: CGFloat)] = [
            (Self.lightSaturation, Self.lightBrightness),
            (Self.midSaturation,   Self.midBrightness),
            (Self.darkSaturation,  Self.darkBrightness),
        ]

        for (index, color) in result.enumerated() {
            let components = hsb(of: color)
            #expect(
                abs(components.h - hue) < 0.005,
                "color[\(index)] hue \(components.h) should match input \(hue)"
            )
            #expect(
                abs(components.s - expected[index].s) < 0.005,
                "color[\(index)] saturation \(components.s) should be \(expected[index].s)"
            )
            #expect(
                abs(components.b - expected[index].b) < 0.005,
                "color[\(index)] brightness \(components.b) should be \(expected[index].b)"
            )
        }
    }

    @Test("slot ordering paints lightest at top, darkest at bottom")
    func slotOrdering() throws {
        let result = ColorEditorControl.deriveColors(fromHue: 0.6)
        try #require(result.count == 3)

        let bs = result.map { hsb(of: $0).b }
        #expect(bs[0] > bs[1], "slot 0 must be brighter than slot 1")
        #expect(bs[1] > bs[2], "slot 1 must be brighter than slot 2")
    }

    @Test(
        "hex round-trip is stable for derived colors",
        arguments: [0.0, 0.08, 0.34, 0.5, 0.6, 0.75, 0.95] as [CGFloat]
    )
    func hexRoundTripStable(hue: CGFloat) throws {
        let derived = ColorEditorControl.deriveColors(fromHue: hue)

        for color in derived {
            let firstHex = color.hexString
            let parsed = try #require(Color(hex: firstHex))
            let secondHex = parsed.hexString
            #expect(
                firstHex == secondHex,
                "hex round-trip drifted: \(firstHex) → \(secondHex) for hue \(hue)"
            )
        }
    }

    @Test("randomDerivedColors never seeds from a degenerate (S:0) preset")
    func randomSourceSkipsDegenerates() throws {
        for _ in 0..<200 {
            let colors = ColorEditorControl.randomDerivedColors()
            try #require(colors.count == 3)
            for color in colors {
                let components = hsb(of: color)
                #expect(
                    components.s > 0.0,
                    "saturation \(components.s) implies seed came from a White/Black preset"
                )
            }
        }
    }

    // MARK: - Helpers

    private func hsb(of color: Color) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        let uiColor = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }
}
