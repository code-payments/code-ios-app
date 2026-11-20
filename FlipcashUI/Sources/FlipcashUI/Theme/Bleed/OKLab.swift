//
//  OKLab.swift
//  FlipcashUI
//

import Foundation

/// OKLab / OKLCH (Björn Ottosson), a perceptual space where lightness and chroma behave, so the
/// palette can clamp lightness and scale saturation without hue shifts or muddy results.
nonisolated struct OKLab: Hashable, Sendable {
    var l: Double
    var a: Double
    var b: Double

    /// A color from its OKLab coordinates.
    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    /// The color of linear-light sRGB components.
    init(linearRed r: Double, green g: Double, blue b: Double) {
        let lms0 = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let lms1 = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let lms2 = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        l = 0.2104542553 * lms0 + 0.7936177850 * lms1 - 0.0040720468 * lms2
        a = 1.9779984951 * lms0 - 2.4285922050 * lms1 + 0.4505937099 * lms2
        self.b = 0.0259040371 * lms0 + 0.7827717662 * lms1 - 0.8086757660 * lms2
    }

    /// The color of a gamma-encoded sRGB value.
    init(_ rgb: BleedRGB) {
        self.init(
            linearRed: BleedRGB.linear(rgb.red),
            green: BleedRGB.linear(rgb.green),
            blue: BleedRGB.linear(rgb.blue)
        )
    }

    /// Linear-light sRGB components, which fall outside 0…1 when the color is out of gamut.
    var linearRGB: (red: Double, green: Double, blue: Double) {
        let lms0 = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let lms1 = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let lms2 = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (
            4.0767416621 * lms0 - 3.3077115913 * lms1 + 0.2309699292 * lms2,
            -1.2684380046 * lms0 + 2.6097574011 * lms1 - 0.3413193965 * lms2,
            -0.0041960863 * lms0 - 0.7034186147 * lms1 + 1.7076147010 * lms2
        )
    }

    /// Whether the color fits inside sRGB.
    var isInGamut: Bool {
        let rgb = linearRGB
        let range = -0.0001...1.0001
        return range.contains(rgb.red) && range.contains(rgb.green) && range.contains(rgb.blue)
    }

    /// The distance from neutral gray.
    var chroma: Double { (a * a + b * b).squareRoot() }

    /// The hue in degrees, 0…360.
    var hue: Double {
        let degrees = atan2(b, a) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// A color from OKLCH coordinates, with `hue` in degrees.
    init(lightness: Double, chroma: Double, hue: Double) {
        let radians = hue * .pi / 180
        self.init(l: lightness, a: chroma * cos(radians), b: chroma * sin(radians))
    }

    /// The color as sRGB, with chroma reduced (lightness and hue kept) until it fits the gamut.
    var gamutMappedRGB: BleedRGB {
        var mapped = self
        if !mapped.isInGamut {
            let hue = self.hue
            var low = 0.0
            var high = chroma
            for _ in 0..<18 {
                let mid = (low + high) / 2
                if OKLab(lightness: l, chroma: mid, hue: hue).isInGamut { low = mid } else { high = mid }
            }
            mapped = OKLab(lightness: l, chroma: low, hue: hue)
        }
        let rgb = mapped.linearRGB
        return BleedRGB(
            red: BleedRGB.encoded(min(max(rgb.red, 0), 1)),
            green: BleedRGB.encoded(min(max(rgb.green, 0), 1)),
            blue: BleedRGB.encoded(min(max(rgb.blue, 0), 1))
        )
    }
}
