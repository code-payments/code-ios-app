//
//  ImageCompressor.swift
//  Flipcash
//

import UIKit

nonisolated enum ImageCompressor {

    /// Normalizes EXIF orientation and caps the image to `maxDimension` on its
    /// longest side. Returns the original image unchanged when already within bounds.
    static func compress(_ original: UIImage, maxDimension: CGFloat = 1024) async -> UIImage {
        await Task.detached(priority: .userInitiated) {
            compressSync(original, maxDimension: maxDimension)
        }.value
    }

    /// Returns `original` redrawn upright, baking any EXIF rotation into the
    /// pixels.
    static func normalizedSync(_ original: UIImage) -> UIImage {
        guard original.imageOrientation != .up else {
            return original
        }

        // UIImage from Files can carry EXIF rotation that causes layout jumps
        // when set as view content.
        return render(original, at: original.size, scale: original.scale)
    }

    /// Synchronous variant for tests. Production callers should use the async
    /// form which offloads the CPU work.
    static func compressSync(_ original: UIImage, maxDimension: CGFloat = 1024) -> UIImage {
        let size = original.size
        guard size.width > maxDimension || size.height > maxDimension else {
            return normalizedSync(original)
        }

        let scale = maxDimension / max(size.width, size.height)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        // Drawing honours `imageOrientation`, so the downscale also normalizes —
        // no separate upright pass is needed on this path.
        return render(original, at: targetSize, scale: 1)
    }

    /// `maxDimension` is a pixel budget, so the renderer's scale is pinned
    /// rather than left at the screen's — the default would emit three times the
    /// requested pixels per axis on every shipping device.
    private static func render(_ image: UIImage, at size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
