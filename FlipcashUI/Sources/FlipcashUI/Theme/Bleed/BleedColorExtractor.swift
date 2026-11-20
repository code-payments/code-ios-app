//
//  BleedColorExtractor.swift
//  FlipcashUI
//

import CoreGraphics
import UIKit

/// Extracts the "bleed" color of an image: the color of its bottom edge, so a gradient from the
/// image into that color reads as the image continuing.
///
/// Samples the bottom strip into a tiny bitmap, weights pixels toward the bottom edge and the
/// horizontal center, then takes the dominant k-means cluster in OKLab. Pure and thread-safe; call
/// it off the main actor.
nonisolated enum BleedColorExtractor {

    /// The fraction of the image's height, from the bottom edge, that is sampled.
    private static let sampleFraction = 0.26

    /// The width of the downsampled copy the strip is cropped from; the sample is clustered into a
    /// 48 px bitmap anyway, so decoding a full-size cover would only compete with the first frame.
    private static let decodeWidth: CGFloat = 192

    /// The bleed color of `image`, extracted off the main actor.
    @concurrent
    static func extract(image: UIImage) async -> BleedRGB? {
        guard image.size.width > 0 else { return nil }
        let scale = min(1, decodeWidth / (image.size.width * image.scale))
        let target = CGSize(
            width: (image.size.width * image.scale * scale).rounded(),
            height: (image.size.height * image.scale * scale).rounded()
        )
        let downsampled = scale < 1 ? image.preparingThumbnail(of: target) : image
        guard let cgImage = (downsampled ?? image).cgImage else { return nil }
        return extract(from: cgImage)
    }

    /// The bleed color of the bottom strip of `image`.
    static func extract(from image: CGImage) -> BleedRGB? {
        guard let samples = sampleBottomStrip(of: image, fraction: sampleFraction),
              !samples.isEmpty else { return nil }
        return dominantCluster(samples) ?? weightedAverage(samples)
    }

    // MARK: - Sampling

    private struct Sample {
        /// Linear-light sRGB.
        var red: Double
        var green: Double
        var blue: Double
        var weight: Double
    }

    private static let sampleWidth = 48

    private static func sampleBottomStrip(of image: CGImage, fraction: Double) -> [Sample]? {
        let imageWidth = image.width
        let imageHeight = image.height
        guard imageWidth > 0, imageHeight > 0 else { return nil }

        let stripHeight = max(1, Int((Double(imageHeight) * fraction).rounded()))
        let cropRect = CGRect(x: 0, y: imageHeight - stripHeight, width: imageWidth, height: stripHeight)
        guard let strip = image.cropping(to: cropRect) else { return nil }

        let width = sampleWidth
        let height = min(24, max(4, Int((Double(width) * Double(stripHeight) / Double(imageWidth)).rounded())))
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var samples: [Sample] = []
        samples.reserveCapacity(width * height)
        for row in 0..<height {
            // Row 0 is the top of the strip; weight grows toward the image's bottom edge.
            let vertical = height > 1 ? Double(row) / Double(height - 1) : 1
            let rowWeight = 0.3 + 0.7 * pow(vertical, 1.6)
            for column in 0..<width {
                let horizontal = width > 1 ? Double(column) / Double(width - 1) : 0.5
                let columnWeight = 0.35 + 0.65 * (1 - abs(horizontal * 2 - 1))
                let offset = row * bytesPerRow + column * 4
                samples.append(Sample(
                    red: BleedRGB.linear(Double(pixels[offset]) / 255),
                    green: BleedRGB.linear(Double(pixels[offset + 1]) / 255),
                    blue: BleedRGB.linear(Double(pixels[offset + 2]) / 255),
                    weight: rowWeight * columnWeight
                ))
            }
        }
        return samples
    }

    // MARK: - Average

    private static func weightedAverage(_ samples: [Sample]) -> BleedRGB {
        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for sample in samples {
            red += sample.red * sample.weight
            green += sample.green * sample.weight
            blue += sample.blue * sample.weight
            total += sample.weight
        }
        guard total > 0 else { return BleedRGB(red: 0.5, green: 0.5, blue: 0.5) }
        return BleedRGB(
            red: BleedRGB.encoded(red / total),
            green: BleedRGB.encoded(green / total),
            blue: BleedRGB.encoded(blue / total)
        )
    }

    // MARK: - K-means

    private static func dominantCluster(_ samples: [Sample], k: Int = 3, iterations: Int = 10) -> BleedRGB? {
        let points = samples.map { OKLab(linearRed: $0.red, green: $0.green, blue: $0.blue) }
        let weights = samples.map(\.weight)
        guard points.count >= k else { return nil }

        // Deterministic seeds: lightness quantiles (dark, mid, light).
        let byLightness = points.indices.sorted { points[$0].l < points[$1].l }
        var centers = (0..<k).map { index in
            points[byLightness[(byLightness.count - 1) * (2 * index + 1) / (2 * k)]]
        }
        var assignment = [Int](repeating: 0, count: points.count)

        for _ in 0..<iterations {
            for (index, point) in points.enumerated() {
                var best = 0
                var bestDistance = Double.infinity
                for (centerIndex, center) in centers.enumerated() {
                    let dl = point.l - center.l, da = point.a - center.a, db = point.b - center.b
                    let distance = dl * dl + da * da + db * db
                    if distance < bestDistance {
                        bestDistance = distance
                        best = centerIndex
                    }
                }
                assignment[index] = best
            }
            var sums = [(l: Double, a: Double, b: Double, w: Double)](repeating: (0, 0, 0, 0), count: k)
            for (index, point) in points.enumerated() {
                let cluster = assignment[index]
                let weight = weights[index]
                sums[cluster].l += point.l * weight
                sums[cluster].a += point.a * weight
                sums[cluster].b += point.b * weight
                sums[cluster].w += weight
            }
            for cluster in 0..<k where sums[cluster].w > 0 {
                let sum = sums[cluster]
                centers[cluster] = OKLab(l: sum.l / sum.w, a: sum.a / sum.w, b: sum.b / sum.w)
            }
        }

        var clusterWeights = [Double](repeating: 0, count: k)
        for (index, cluster) in assignment.enumerated() {
            clusterWeights[cluster] += weights[index]
        }
        // Dominance, nudged toward colorful clusters and away from crushed shadows / blown highlights.
        let scored = centers.indices.map { cluster -> (Int, Double) in
            let center = centers[cluster]
            var score = clusterWeights[cluster] * (1 + 2.5 * center.chroma)
            if center.l < 0.18 || center.l > 0.95 { score *= 0.6 }
            return (cluster, score)
        }
        guard let winner = scored.max(by: { $0.1 < $1.1 })?.0 else { return nil }
        return centers[winner].gamutMappedRGB
    }
}
