//
//  ColorEditorControlTests.swift
//  FlipcashTests
//
//  Guards against a regression where the swatch row was shown left-to-right
//  but painted the bill bottom-to-top, because the editor reversed the colors
//  array on both read and write.
//

import Testing
import SwiftUI
import FlipcashUI
@testable import Flipcash

@Suite("ColorEditorControl")
struct ColorEditorControlTests {

    @Test(
        "initialStops preserves input order, position-for-position",
        arguments: [
            [0.0],
            [0.0, 0.6],
            [0.0, 0.33, 0.66],
        ] as [[CGFloat]]
    )
    func initialStopsPreservesOrder(hues: [CGFloat]) throws {
        let colors = hues.map { Color(hue: $0, saturation: 0.8, brightness: 0.9) }

        let stops = ColorEditorControl.initialStops(from: colors)

        try #require(stops.count == hues.count)
        for (index, expectedHue) in hues.enumerated() {
            #expect(
                abs(stops[index].hue - expectedHue) < 0.001,
                "stop[\(index)] hue \(stops[index].hue) should match input[\(index)] hue \(expectedHue)"
            )
        }
    }

    @Test("input beyond maxStops is truncated from the tail, leftmost entries kept")
    func truncatesToMaxStops() throws {
        let hues: [CGFloat] = [0.0, 0.2, 0.4, 0.6, 0.8]
        let colors = hues.map { Color(hue: $0, saturation: 0.8, brightness: 0.9) }

        let stops = ColorEditorControl.initialStops(from: colors)

        try #require(stops.count == ColorEditorControl.maxStops)
        for index in 0..<ColorEditorControl.maxStops {
            #expect(abs(stops[index].hue - hues[index]) < 0.001)
        }
    }

    @Test("empty input returns a single default stop")
    func emptyInputReturnsDefault() throws {
        let stops = ColorEditorControl.initialStops(from: [])

        try #require(stops.count == 1)
        #expect(abs(stops[0].hue - 0.6) < 0.001)
        #expect(abs(stops[0].saturation - 0.7) < 0.001)
        #expect(abs(stops[0].brightness - 0.9) < 0.001)
    }
}

@MainActor
@Suite("ColorEditorControl.parsePastedPalette")
struct ColorEditorControlPasteTests {

    // MARK: - Valid inputs

    @Test("Exact format produced by Copy yields three colors")
    func exactFormat() throws {
        let pasted = try #require(
            ColorEditorControl.parsePastedPalette("#FF0000, #00FF00, #0000FF")
        )
        #expect(pasted.count == 3)
        #expect(pasted[0].hexString == "#FF0000")
        #expect(pasted[1].hexString == "#00FF00")
        #expect(pasted[2].hexString == "#0000FF")
    }

    @Test("Lowercase hex digits are accepted")
    func lowercase() throws {
        let pasted = try #require(
            ColorEditorControl.parsePastedPalette("#ff0000, #00ff00, #0000ff")
        )
        #expect(pasted.count == 3)
    }

    @Test("Trailing newline is tolerated")
    func trailingNewline() throws {
        let pasted = try #require(
            ColorEditorControl.parsePastedPalette("#FF0000, #00FF00, #0000FF\n")
        )
        #expect(pasted.count == 3)
    }

    @Test("Missing whitespace around commas is tolerated")
    func noSpaces() throws {
        let pasted = try #require(
            ColorEditorControl.parsePastedPalette("#FF0000,#00FF00,#0000FF")
        )
        #expect(pasted.count == 3)
    }

    @Test("Outer whitespace is tolerated")
    func outerWhitespace() throws {
        let pasted = try #require(
            ColorEditorControl.parsePastedPalette("  #FF0000, #00FF00, #0000FF  ")
        )
        #expect(pasted.count == 3)
    }

    @Test("Round-trip from Copy format yields the same hex strings")
    func roundTripFromCopy() throws {
        let original: [Color] = [
            Color(hue: 0.00, saturation: 0.9, brightness: 0.95),
            Color(hue: 0.34, saturation: 0.8, brightness: 0.90),
            Color(hue: 0.60, saturation: 0.75, brightness: 0.85),
        ]
        let copyOutput = original.map(\.hexString).joined(separator: ", ")
        let parsed = try #require(ColorEditorControl.parsePastedPalette(copyOutput))
        #expect(parsed.map(\.hexString) == original.map(\.hexString))
    }

    // MARK: - Invalid inputs

    @Test("Nil input returns nil")
    func nilInput() {
        #expect(ColorEditorControl.parsePastedPalette(nil) == nil)
    }

    @Test("Empty string returns nil")
    func emptyInput() {
        #expect(ColorEditorControl.parsePastedPalette("") == nil)
    }

    @Test(
        "Wrong number of hexes returns nil",
        arguments: [
            "#FF0000",
            "#FF0000, #00FF00",
            "#FF0000, #00FF00, #0000FF, #FFFFFF",
        ]
    )
    func wrongCount(input: String) {
        #expect(ColorEditorControl.parsePastedPalette(input) == nil)
    }

    @Test("Non-hex content returns nil")
    func nonHexContent() {
        #expect(ColorEditorControl.parsePastedPalette("red, green, blue") == nil)
    }

    @Test("Shorthand hex returns nil")
    func shorthandHex() {
        #expect(ColorEditorControl.parsePastedPalette("#FFF, #000, #00F") == nil)
    }

    @Test("Hex with alpha (8 chars) returns nil")
    func hexWithAlpha() {
        #expect(
            ColorEditorControl.parsePastedPalette("#FF0000FF, #00FF00FF, #0000FFFF") == nil
        )
    }

    @Test("Missing # prefix returns nil")
    func missingHashPrefix() {
        #expect(
            ColorEditorControl.parsePastedPalette("FF0000, 00FF00, 0000FF") == nil
        )
    }
}
