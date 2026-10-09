//
//  BlurHashEncoder.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CoreGraphics
import Foundation

/// The BlurHash encoder, ported from the public-domain reference implementation. It lives here, not
/// beside the decoder in FlipcashUI, so a process that cannot link the UI can hash the photos it
/// uploads.
public enum BlurHashEncoder {

    /// Encodes `image` into a hash with `componentsX` × `componentsY` components (each 1…9), or nil
    /// when the image cannot be drawn.
    ///
    /// The image is sampled at a small fixed size first: a hash keeps only the lowest frequencies, so
    /// more pixels change nothing but the cost. Squashing it to a square is harmless for the same
    /// reason; the decoder stretches back to whatever aspect it is drawn at.
    public static func encode(_ image: CGImage, componentsX: Int, componentsY: Int) -> String? {
        guard (1...9).contains(componentsX), (1...9).contains(componentsY) else { return nil }
        let side = 32
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * bytesPerRow)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        return encode(rgb: pixels, width: side, height: side, bytesPerRow: bytesPerRow, componentsX: componentsX, componentsY: componentsY)
    }

    /// Encodes 8-bit sRGB pixels laid out as RGBx rows, the reference implementation's algorithm.
    static func encode(rgb pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int, componentsX: Int, componentsY: Int) -> String {
        var linear = [SIMD3<Float>](repeating: .zero, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                linear[y * width + x] = SIMD3(
                    srgbToLinear(Int(pixels[offset])),
                    srgbToLinear(Int(pixels[offset + 1])),
                    srgbToLinear(Int(pixels[offset + 2]))
                )
            }
        }

        var factors: [SIMD3<Float>] = []
        for j in 0..<componentsY {
            for i in 0..<componentsX {
                let normalisation: Float = (i == 0 && j == 0) ? 1 : 2
                var sum = SIMD3<Float>.zero
                for y in 0..<height {
                    let basisY = cosf(.pi * Float(j) * Float(y) / Float(height))
                    for x in 0..<width {
                        let basis = normalisation * cosf(.pi * Float(i) * Float(x) / Float(width)) * basisY
                        sum += basis * linear[y * width + x]
                    }
                }
                factors.append(sum / Float(width * height))
            }
        }

        let dc = factors[0]
        let ac = factors.dropFirst()

        var hash = encode83((componentsX - 1) + (componentsY - 1) * 9, length: 1)
        let maxValue: Float
        if let actualMax = ac.map({ max(abs($0.x), abs($0.y), abs($0.z)) }).max() {
            let quantisedMax = max(0, min(82, Int(floorf(actualMax * 166 - 0.5))))
            maxValue = Float(quantisedMax + 1) / 166
            hash += encode83(quantisedMax, length: 1)
        } else {
            maxValue = 1
            hash += encode83(0, length: 1)
        }

        hash += encode83((linearToSrgb(dc.x) << 16) + (linearToSrgb(dc.y) << 8) + linearToSrgb(dc.z), length: 4)
        for factor in ac {
            hash += encode83(encodeAc(factor, maxValue), length: 2)
        }
        return hash
    }

    private static func encodeAc(_ value: SIMD3<Float>, _ maxValue: Float) -> Int {
        func quantise(_ component: Float) -> Int {
            let scaled = component / maxValue
            let root = scaled < 0 ? -sqrtf(-scaled) : sqrtf(scaled)
            return max(0, min(18, Int(floorf(root * 9 + 9.5))))
        }
        return quantise(value.x) * 19 * 19 + quantise(value.y) * 19 + quantise(value.z)
    }

    private static func encode83(_ value: Int, length: Int) -> String {
        var result = ""
        for i in 1...length {
            var divisor = 1
            for _ in 0..<(length - i) { divisor *= 83 }
            result.append(alphabet[(value / divisor) % 83])
        }
        return result
    }

    private static func srgbToLinear(_ colorEnc: Int) -> Float {
        let v = Float(colorEnc) / 255
        return v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4)
    }

    private static func linearToSrgb(_ value: Float) -> Int {
        let v = min(max(value, 0), 1)
        let srgb = v <= 0.0031308 ? v * 12.92 : 1.055 * powf(v, 1 / 2.4) - 0.055
        return Int(srgb * 255 + 0.5)
    }

    private static let alphabet = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"
    )
}
