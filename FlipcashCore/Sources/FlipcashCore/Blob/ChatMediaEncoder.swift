//
//  ChatMediaEncoder.swift
//  FlipcashCore
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Re-encodes a chat photo as an upright JPEG at its `ChatMediaDownscale` target, stepping
/// quality down the ladder until the bytes fit the policy's size ceiling.
///
/// The fixture pins the ladder, not the encoded bytes — encoders differ across OS versions.
public struct ChatMediaEncoder: Sendable {

    public enum Error: Swift.Error, Equatable {
        /// The image could not be drawn or encoded at all.
        case encodingFailed
        /// Every quality on the ladder produced more bytes than the ceiling.
        case tooLarge
    }

    /// The MIME type every encoded photo is uploaded as.
    public static let mimeType = "image/jpeg"

    /// JPEG qualities tried in order, highest first.
    public static let qualityLadder: [Double] = [0.9, 0.8, 0.7, 0.6]

    private let encodeJPEG: @Sendable (CGImage, Double) -> Data?

    /// Creates an encoder backed by ImageIO.
    public init() {
        self.init(encodeJPEG: Self.jpeg)
    }

    init(encodeJPEG: @escaping @Sendable (CGImage, Double) -> Data?) {
        self.encodeJPEG = encodeJPEG
    }

    /// Returns `image` drawn upright at `target` and encoded at the highest ladder quality
    /// whose stripped bytes fit `maxSizeBytes`.
    ///
    /// `orientation` is the source's display orientation; `target` is in display space, so
    /// its edges are swapped relative to `image` for a sideways capture.
    public func encode(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        target: ChatMediaDownscale.Target,
        maxSizeBytes: Int
    ) throws -> Data {
        guard let upright = Self.render(image, orientation: orientation, target: target) else {
            throw Error.encodingFailed
        }

        var encodedAny = false
        for quality in Self.qualityLadder {
            guard let data = encodeJPEG(upright, quality) else { continue }
            encodedAny = true

            // Measured after stripping, since the stripped bytes are what the reservation signs.
            let stripped = JPEGMetadata.stripped(data)
            if stripped.count <= maxSizeBytes {
                return stripped
            }
        }

        throw encodedAny ? Error.tooLarge : Error.encodingFailed
    }

    // MARK: - Drawing -

    /// Returns `image` redrawn at `target` with `orientation` baked into the pixels, on an
    /// opaque white background since JPEG carries no alpha.
    static func render(_ image: CGImage, orientation: CGImagePropertyOrientation, target: ChatMediaDownscale.Target) -> CGImage? {
        let width = CGFloat(target.width)
        let height = CGFloat(target.height)

        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!

        guard let context = CGContext(
            data: nil,
            width: target.width,
            height: target.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        var transform = CGAffineTransform.identity
        var drawSize = CGSize(width: width, height: height)

        switch orientation {
        case .up, .upMirrored:
            break
        case .down, .downMirrored:
            transform = transform.translatedBy(x: width, y: height).rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: width, y: 0).rotated(by: .pi / 2)
            drawSize = CGSize(width: height, height: width)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: height).rotated(by: -.pi / 2)
            drawSize = CGSize(width: height, height: width)
        }

        switch orientation {
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: drawSize.width, y: 0).scaledBy(x: -1, y: 1)
        case .up, .down, .left, .right:
            break
        }

        context.concatenate(transform)
        context.draw(image, in: CGRect(origin: .zero, size: drawSize))

        return context.makeImage()
    }

    // MARK: - Encoding -

    /// Encodes `image` as a JPEG at `quality`, carrying no source metadata.
    static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return output as Data
    }
}
