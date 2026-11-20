//
//  BleedPaletteTests.swift
//  FlipcashTests
//

import Testing
import SwiftUI
import UIKit
@testable import Flipcash
@testable import FlipcashUI

/// Holds the light bleed rule ("Tint") to its bounds on the public group page's covers, and pins
/// the dark rule to the values it produced before light mode.
@MainActor
@Suite("Bleed palette")
struct BleedPaletteTests {

    /// The plan's eight sample covers plus a near-black and a near-white.
    enum Cover: UInt32, CaseIterable, Sendable {
        case navy = 0x1E2A4A
        case sunset = 0xE07A3A
        case forest = 0x2F5D3A
        case rose = 0xE8A0B8
        case night = 0x151515
        case sky = 0x7FB6E8
        case sand = 0xCDB894
        case plum = 0x5B2A5E
        case nearBlack = 0x050505
        case nearWhite = 0xFAFAFA

        var rgb: BleedRGB {
            BleedRGB(
                red: Double((rawValue >> 16) & 0xFF) / 255,
                green: Double((rawValue >> 8) & 0xFF) / 255,
                blue: Double(rawValue & 0xFF) / 255
            )
        }

        /// The dark page the rule produced before light mode.
        var darkBackground: BleedRGB {
            switch self {
            case .navy:      BleedRGB(red: 0.016572175154691029, green: 0.047336197543280299, blue: 0.18920150204773323)
            case .sunset:    BleedRGB(red: 0.34763713231356702, green: 0.14557464850887883, blue: 0)
            case .forest:    BleedRGB(red: 0, green: 0.14851712121259042, blue: 0.0455444632418174)
            case .rose:      BleedRGB(red: 0.4185169648871212, green: 0.13242612746860563, blue: 0.25277207789999079)
            case .night:     BleedRGB(red: 0.058802088014863023, green: 0.028110247336900658, blue: 0.0023539884462891202)
            case .sky:       BleedRGB(red: 0, green: 0.25278870323851205, blue: 0.42541174680210564)
            case .sand:      BleedRGB(red: 0.32542297992324426, green: 0.24084237104835149, blue: 0.074714619442483671)
            case .plum:      BleedRGB(red: 0.17455562236492236, green: 0, blue: 0.18777721141422998)
            case .nearBlack: BleedRGB(red: 0.04323663359528352, green: 0.017520263178749843, blue: 0)
            case .nearWhite: BleedRGB(red: 0.3734533328799633, green: 0.33154633968286457, blue: 0.27557850895515568)
            }
        }

        /// The dark cards' tint the rule produced before light mode.
        var darkControlTint: BleedRGB {
            switch self {
            case .navy:      BleedRGB(red: 0.084231090826810684, green: 0.14175717303743354, blue: 0.31683897538310091)
            case .sunset:    BleedRGB(red: 0.48491141226487228, green: 0.23865608510197689, blue: 0.076148000559418033)
            case .forest:    BleedRGB(red: 0.0775326058730538, green: 0.2541994537425013, blue: 0.12772068297737474)
            case .rose:      BleedRGB(red: 0.56468718879308022, green: 0.21947721496598582, blue: 0.35916880773018511)
            case .night:     BleedRGB(red: 0.15414855768298574, green: 0.11277336046281916, blue: 0.054376784314334438)
            case .sky:       BleedRGB(red: 0.0875501040169471, green: 0.36300152151861148, blue: 0.57256441996516683)
            case .sand:      BleedRGB(red: 0.44752409746581884, green: 0.34484740989705887, blue: 0.15157325477395908)
            case .plum:      BleedRGB(red: 0.2935757841401076, green: 0.081132902161967752, blue: 0.30817319609636323)
            case .nearBlack: BleedRGB(red: 0.13667079665082985, green: 0.095941034315598417, blue: 0.041168422107146142)
            case .nearWhite: BleedRGB(red: 0.49195598271821778, green: 0.4413185599997122, blue: 0.37379537533180762)
            }
        }
    }

    /// Slack for the gamut search's clamp, which can nudge lightness and chroma by a hair.
    private static let gamutSlack = 0.0005

    private func makePalette(_ cover: Cover, _ colorScheme: ColorScheme) -> BleedPalette {
        BleedPalette(base: cover.rgb, settings: PublicGroupLook.settings, colorScheme: colorScheme)
    }

    // MARK: - Light -

    @Test("The light page's lightness stays within 0.91…0.97", arguments: Cover.allCases)
    func lightLightness(_ cover: Cover) throws {
        let page = try #require(makePalette(cover, .light).backgroundRGB)
        let lightness = OKLab(page).l
        #expect(lightness >= 0.91 - Self.gamutSlack)
        #expect(lightness <= 0.97 + Self.gamutSlack)
    }

    @Test("The light page keeps at most 0.03 chroma", arguments: Cover.allCases)
    func lightChroma(_ cover: Cover) throws {
        let page = try #require(makePalette(cover, .light).backgroundRGB)
        #expect(OKLab(page).chroma <= 0.03 + Self.gamutSlack)
    }

    @Test("Ink, and ink at 65%, keep 4.5:1 on the light page", arguments: Cover.allCases)
    func lightInkContrast(_ cover: Cover) throws {
        let page = try #require(makePalette(cover, .light).backgroundRGB)
        #expect(BleedRGB.black.contrast(with: page) >= 4.5)
        #expect(page.blended(with: .black, opacity: 0.65).contrast(with: page) >= 4.5)
    }

    @Test("The light palette's secondary text is flat ink that keeps 4.5:1 on the page and on its cards", arguments: Cover.allCases)
    func lightSecondaryStyles(_ cover: Cover) throws {
        let palette = makePalette(cover, .light)
        let page = try #require(palette.backgroundRGB)
        let tint = rgb(of: palette.controlTint)

        #expect(palette.secondaryTextStyle.blendMode == .normal)
        #expect(palette.controlSecondaryTextStyle.blendMode == .normal)
        #expect(page.blended(with: .black, opacity: alpha(of: palette.secondaryTextStyle.color)).contrast(with: page) >= 4.5)
        #expect(tint.blended(with: .black, opacity: alpha(of: palette.controlSecondaryTextStyle.color)).contrast(with: tint) >= 4.5)
        #expect(BleedRGB.black.contrast(with: tint) >= 4.5)
    }

    @Test("Each palette reports the scheme it was built for")
    func colorSchemes() {
        #expect(makePalette(.navy, .light).colorScheme == .light)
        #expect(makePalette(.navy, .dark).colorScheme == .dark)
        #expect(BleedPalette.placeholder(for: .light).colorScheme == .light)
        #expect(BleedPalette.placeholder.colorScheme == .dark)
    }

    @Test("The palette cache keeps one palette per appearance")
    func cacheKeyedByScheme() {
        let store = BleedColorStore()
        let base = Cover.sky.rgb
        let dark = store.palette(for: base, settings: PublicGroupLook.settings, colorScheme: .dark)
        let light = store.palette(for: base, settings: PublicGroupLook.settings, colorScheme: .light)
        #expect(dark.colorScheme == .dark)
        #expect(light.colorScheme == .light)
        #expect(dark.backgroundRGB != light.backgroundRGB)
    }

    @Test("The public group page's settings are the engine's tuned defaults")
    func lookMatchesDefaults() {
        #expect(PublicGroupLook.settings == BleedSettings.default)
    }

    // MARK: - Dark -

    @Test("The dark page is what it was before light mode", arguments: Cover.allCases)
    func darkBackgroundUnchanged(_ cover: Cover) throws {
        let page = try #require(makePalette(cover, .dark).backgroundRGB)
        #expect(close(page, cover.darkBackground, within: 1e-7))
    }

    @Test("The dark cards' tint is what it was before light mode", arguments: Cover.allCases)
    func darkControlTintUnchanged(_ cover: Cover) {
        #expect(close(rgb(of: makePalette(cover, .dark).controlTint), cover.darkControlTint, within: 1e-4))
    }

    @Test("Dark secondary text is still vibrant white at 60%", arguments: Cover.allCases)
    func darkSecondaryUnchanged(_ cover: Cover) {
        let palette = makePalette(cover, .dark)
        #expect(palette.secondaryTextStyle.blendMode == .plusLighter)
        #expect(abs(alpha(of: palette.secondaryTextStyle.color) - 0.6) < 1e-4)
        #expect(palette.controlSecondaryTextStyle.blendMode == .plusLighter)
        #expect(abs(alpha(of: palette.controlSecondaryTextStyle.color) - 0.6) < 1e-4)
    }
}

// MARK: - Helpers -

private func components(of color: Color) -> [Double] {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return [red, green, blue, alpha].map(Double.init)
}

private func rgb(of color: Color) -> BleedRGB {
    let parts = components(of: color)
    return BleedRGB(red: parts[0], green: parts[1], blue: parts[2])
}

private func alpha(of color: Color) -> Double {
    components(of: color)[3]
}

private func close(_ lhs: BleedRGB, _ rhs: BleedRGB, within tolerance: Double) -> Bool {
    abs(lhs.red - rhs.red) < tolerance && abs(lhs.green - rhs.green) < tolerance && abs(lhs.blue - rhs.blue) < tolerance
}
