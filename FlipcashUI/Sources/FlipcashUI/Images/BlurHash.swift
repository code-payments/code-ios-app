//
//  BlurHash.swift
//  FlipcashUI
//

import SwiftUI
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

    /// An sRGB colour as the three bytes a BlurHash stores it in.
    public struct RGB: Equatable, Sendable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// The colour as a SwiftUI `Color` in the sRGB space.
        public var color: Color {
            Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
        }
    }

    /// The image's average colour, read from the hash's DC component without decoding the image,
    /// or nil when `hash` is malformed by the same rules `decode` applies.
    ///
    /// Cross-platform: `test-vectors/blurhash_average.json`.
    public static func averageColor(blurHash hash: String?) -> RGB? {
        guard let hash, hash.count >= 6 else { return nil }

        let chars = Array(hash)
        guard chars.allSatisfy({ alphabetIndex[$0] != nil }) else { return nil }

        guard let sizeFlag = decode83(chars, 0, 1) else { return nil }
        let numCompX = sizeFlag % 9 + 1
        let numCompY = sizeFlag / 9 + 1
        guard chars.count == 4 + 2 * numCompX * numCompY else { return nil }

        guard let dc = decode83(chars, 2, 6) else { return nil }
        return RGB(red: UInt8(dc >> 16 & 255), green: UInt8(dc >> 8 & 255), blue: UInt8(dc & 255))
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

    // MARK: - Encode -

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
