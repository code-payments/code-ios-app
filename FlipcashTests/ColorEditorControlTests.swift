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
