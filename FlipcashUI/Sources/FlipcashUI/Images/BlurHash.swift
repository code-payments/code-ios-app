//
//  BlurHash.swift
//  FlipcashUI
//

import UIKit

/// Decoder for [BlurHash](https://blurha.sh) strings — the compact, blurred image preview that
/// ships in a media item's `ImageMetadata`. Decode it into a tiny image and let the image layer
/// scale it up as an instant placeholder while the real (larger) image downloads.
///
/// Ported from the public-domain reference implementation. A hash only encodes a handful of DCT
/// components, so decode at a low resolution (a couple dozen pixels) — anything larger just wastes
/// cycles for no visible gain.
nonisolated public enum BlurHash {

    /// Decodes `hash` into a `width`×`height` image, or nil when the string is malformed. `punch`
    /// adjusts contrast (1 = as encoded).
    public static func decode(_ hash: String?, width: Int, height: Int, punch: Float = 1) -> UIImage? {
        guard let hash, hash.count >= 6, width > 0, height > 0 else { return nil }

        let chars = Array(hash)

        guard let sizeFlag = decode83(chars, 0, 1) else { return nil }
        let numCompX = sizeFlag % 9 + 1
        let numCompY = sizeFlag / 9 + 1
        guard chars.count == 4 + 2 * numCompX * numCompY else { return nil }

        guard let quantisedMaxAc = decode83(chars, 1, 2) else { return nil }
        let maxAc = Float(quantisedMaxAc + 1) / 166

        var colors = [SIMD3<Float>](repeating: .zero, count: numCompX * numCompY)
        for i in 0..<colors.count {
            if i == 0 {
                guard let value = decode83(chars, 2, 6) else { return nil }
                colors[i] = decodeDc(value)
            } else {
                let from = 4 + i * 2
                guard let value = decode83(chars, from, from + 2) else { return nil }
                colors[i] = decodeAc(value, maxAc * punch)
            }
        }

        return composeImage(width: width, height: height, numCompX: numCompX, numCompY: numCompY, colors: colors)
    }

    private static func decode83(_ chars: [Character], _ from: Int, _ to: Int) -> Int? {
        var result = 0
        for i in from..<to {
            guard let index = alphabetIndex[chars[i]] else { return nil }
            result = result * 83 + index
        }
        return result
    }

    private static func decodeDc(_ colorEnc: Int) -> SIMD3<Float> {
        SIMD3(
            srgbToLinear(colorEnc >> 16 & 255),
            srgbToLinear(colorEnc >> 8 & 255),
            srgbToLinear(colorEnc & 255)
        )
    }

    private static func decodeAc(_ value: Int, _ maxAc: Float) -> SIMD3<Float> {
        SIMD3(
            signPow(Float(value / (19 * 19) - 9) / 9) * maxAc,
            signPow(Float(value / 19 % 19 - 9) / 9) * maxAc,
            signPow(Float(value % 19 - 9) / 9) * maxAc
        )
    }

    /// sign(value) * value² — the reference impl's quantisation curve.
    private static func signPow(_ value: Float) -> Float {
        let squared = value * value
        return value < 0 ? -squared : squared
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

    private static func composeImage(
        width: Int,
        height: Int,
        numCompX: Int,
        numCompY: Int,
        colors: [SIMD3<Float>]
    ) -> UIImage? {
        // Precompute the cosine basis for each axis so the inner pixel loop is just multiplies.
        var cosX = [Float](repeating: 0, count: width * numCompX)
        for x in 0..<width {
            for i in 0..<numCompX {
                cosX[x * numCompX + i] = cos(Float.pi * Float(x) * Float(i) / Float(width))
            }
        }
        var cosY = [Float](repeating: 0, count: height * numCompY)
        for y in 0..<height {
            for j in 0..<numCompY {
                cosY[y * numCompY + j] = cos(Float.pi * Float(y) * Float(j) / Float(height))
            }
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var color = SIMD3<Float>.zero
                for j in 0..<numCompY {
                    let cy = cosY[y * numCompY + j]
                    for i in 0..<numCompX {
                        let basis = cosX[x * numCompX + i] * cy
                        color += colors[j * numCompX + i] * basis
                    }
                }
                let offset = (y * width + x) * 4
                pixels[offset]     = UInt8(linearToSrgb(color.x))
                pixels[offset + 1] = UInt8(linearToSrgb(color.y))
                pixels[offset + 2] = UInt8(linearToSrgb(color.z))
                pixels[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    private static let alphabet = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"
    )

    private static let alphabetIndex: [Character: Int] =
        Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
}

/// Process-wide cache of decoded BlurHash previews, so re-rendering an avatar doesn't re-run the
/// decode. `NSCache` is thread-safe, so the same instance is read from any caller without extra
/// synchronization.
nonisolated public final class BlurHashCache: @unchecked Sendable {

    public static let shared = BlurHashCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
    }

    /// Returns the decoded preview for `hash` at `width`×`height`, decoding and caching on a miss.
    /// Returns nil when the hash is absent or malformed.
    public func image(for hash: String?, width: Int = 24, height: Int = 24) -> UIImage? {
        guard let hash, !hash.isEmpty else { return nil }

        let key = "\(hash)@\(width)x\(height)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = BlurHash.decode(hash, width: width, height: height) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
