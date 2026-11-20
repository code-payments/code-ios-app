//
//  BleedSettings.swift
//  FlipcashUI
//

import Foundation

/// The inputs of the dark bleed palette, defaulting to the values tuned in the Recipes prototype
/// (commit 6e2c13d).
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

    /// The tuned defaults.
    public static let `default` = BleedSettings()

    /// Settings with the tuned defaults for everything not passed.
    public init(
        saturation: Double = 1.2,
        lightnessDark: Double = 0.1,
        lightnessPull: Double = 0.6,
        neutralWarmth: Double = 1,
        vibrantText: Bool = true,
        vibrantOpacity: Double = 0.6
    ) {
        self.saturation = saturation
        self.lightnessDark = lightnessDark
        self.lightnessPull = lightnessPull
        self.neutralWarmth = neutralWarmth
        self.vibrantText = vibrantText
        self.vibrantOpacity = vibrantOpacity
    }
}
