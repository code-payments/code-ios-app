//
//  BleedSettings.swift
//  FlipcashUI
//

import Foundation

/// The inputs of the bleed palette, defaulting to the values tuned in the Recipes prototype
/// (commit 6e2c13d) for the dark page and to the "Tint" strength for the light one.
public nonisolated struct BleedSettings: Hashable, Sendable {

    /// Scales the image's own chroma before the lightness-aware ceiling.
    public var saturation: Double = 1.2
    /// The OKLab lightness the background is pulled toward.
    public var lightnessDark: Double = 0.1
    /// How far toward `lightnessDark` the extracted color moves, 0…1.
    public var lightnessPull: Double = 0.6
    /// How strongly a near-neutral image drifts to a warm neutral.
    public var neutralWarmth: Double = 1
    /// Whether secondary, tertiary and body text are vibrant (plus-lighter) rather than flat.
    public var vibrantText = true
    /// The opacity of vibrant secondary text.
    public var vibrantOpacity: Double = 0.6

    /// Scales the image's own chroma on the light page, before `chromaCeilingLight`.
    public var saturationLight: Double = 0.8
    /// The OKLab lightness the light page is pulled toward.
    public var lightnessLight: Double = 0.97
    /// How far toward `lightnessLight` the extracted color moves, 0…1.
    public var lightnessPullLight: Double = 0.7
    /// The OKLab lightness the light page is held inside.
    public var lightnessRangeLight: ClosedRange<Double> = 0.91...0.97
    /// The most chroma the light page keeps, so it reads as a tint of the image rather than a color.
    public var chromaCeilingLight: Double = 0.03

    /// The tuned defaults.
    public static let `default` = BleedSettings()

    /// Settings with the tuned defaults for everything not passed.
    public init(
        saturation: Double = 1.2,
        lightnessDark: Double = 0.1,
        lightnessPull: Double = 0.6,
        neutralWarmth: Double = 1,
        vibrantText: Bool = true,
        vibrantOpacity: Double = 0.6,
        saturationLight: Double = 0.8,
        lightnessLight: Double = 0.97,
        lightnessPullLight: Double = 0.7,
        lightnessRangeLight: ClosedRange<Double> = 0.91...0.97,
        chromaCeilingLight: Double = 0.03
    ) {
        self.saturation = saturation
        self.lightnessDark = lightnessDark
        self.lightnessPull = lightnessPull
        self.neutralWarmth = neutralWarmth
        self.vibrantText = vibrantText
        self.vibrantOpacity = vibrantOpacity
        self.saturationLight = saturationLight
        self.lightnessLight = lightnessLight
        self.lightnessPullLight = lightnessPullLight
        self.lightnessRangeLight = lightnessRangeLight
        self.chromaCeilingLight = chromaCeilingLight
    }
}
