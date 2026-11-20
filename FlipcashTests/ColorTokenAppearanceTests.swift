//
//  ColorTokenAppearanceTests.swift
//  FlipcashTests
//

import Testing
import SwiftUI
import UIKit
import FlipcashUI

/// Pins each token's dark value to what the app shipped before light mode, and its light value to
/// the light palette, through both the UIKit trait path and the SwiftUI environment path.
@MainActor
@Suite("Colour tokens follow the appearance")
struct ColorTokenAppearanceTests {

    enum Token: String, CaseIterable, Sendable {
        case textMain, textSecondary, backgroundMain, backgroundSecondary, action, backgroundRow, rowSeparator, fillControl

        @MainActor
        var color: Color {
            switch self {
            case .textMain:            .textMain
            case .textSecondary:       .textSecondary
            case .backgroundMain:      .backgroundMain
            case .backgroundSecondary: .backgroundSecondary
            case .action:              .action
            case .backgroundRow:       .backgroundRow
            case .rowSeparator:        .rowSeparator
            case .fillControl:         .fillControl
            }
        }

        var dark: UIColor {
            switch self {
            case .textMain:            srgb(0xFFFFFF)
            case .textSecondary:       srgb(0x7B7B7B)
            case .backgroundMain:      p3(0x12, 0x12, 0x12)
            case .backgroundSecondary: p3(0x25, 0x25, 0x26)
            case .action:              srgb(0xFFFFFF)
            case .backgroundRow:       srgb(0xFFFFFF, 0.05)
            case .rowSeparator:        srgb(0xFFFFFF, 0.1)
            case .fillControl:         srgb(0xFFFFFF, 0.1)
            }
        }

        var light: UIColor {
            switch self {
            case .textMain:            srgb(0x000000)
            case .textSecondary:       srgb(0x606065)
            case .backgroundMain:      srgb(0xFFFFFF)
            case .backgroundSecondary: srgb(0xF2F2F7)
            case .action:              srgb(0x000000)
            case .backgroundRow:       srgb(0x747480, 0.08)
            case .rowSeparator:        srgb(0x3C3C43, 0.29)
            case .fillControl:         srgb(0x787880, 0.16)
            }
        }
    }

    @Test("A dark trait collection resolves the dark value", arguments: Token.allCases)
    func darkTraits(_ token: Token) {
        let resolved = UIColor(token.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(matches(resolved, token.dark))
    }

    @Test("A light trait collection resolves the light value", arguments: Token.allCases)
    func lightTraits(_ token: Token) {
        let resolved = UIColor(token.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(matches(resolved, token.light))
    }

    @Test("A dark SwiftUI environment resolves the dark value", arguments: Token.allCases)
    func darkEnvironment(_ token: Token) {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        #expect(matches(UIColor(Color(token.color.resolve(in: environment))), token.dark))
    }

    @Test("A light SwiftUI environment resolves the light value", arguments: Token.allCases)
    func lightEnvironment(_ token: Token) {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        #expect(matches(UIColor(Color(token.color.resolve(in: environment))), token.light))
    }

    @Test("hexString gives the dark value while the current traits are light")
    func hexStringIsDark() {
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            #expect(Color.backgroundMain.hexString == "#121212")
            #expect(Color.textMain.hexString == "#FFFFFF")
            #expect(Color.textSecondary.hexString == "#7B7B7B")
        }
    }
}

// MARK: - Helpers -

private func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
    UIColor(
        red:   CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >>  8) & 0xFF) / 255,
        blue:  CGFloat( hex        & 0xFF) / 255,
        alpha: alpha
    )
}

private func p3(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> UIColor {
    UIColor(displayP3Red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
}

/// Compares in extended sRGB to within half an 8-bit step, so a display-P3 asset matches its own components.
private func matches(_ lhs: UIColor, _ rhs: UIColor) -> Bool {
    zip(components(lhs), components(rhs)).allSatisfy { abs($0 - $1) < 0.5 / 255 }
}

private func components(_ color: UIColor) -> [CGFloat] {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return [red, green, blue, alpha]
}
