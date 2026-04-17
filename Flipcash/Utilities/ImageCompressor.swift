//
//  ImageCompressor.swift
//  Flipcash
//

import UIKit

enum ImageCompressor {

    /// Normalizes EXIF orientation and caps the image to `maxDimension` on its
    /// longest side. Returns the original image unchanged when already within bounds.
    static func compress(_ original: UIImage, maxDimension: CGFloat = 1024) async -> UIImage {
        await Task.detached(priority: .userInitiated) {
            compressSync(original, maxDimension: maxDimension)
        }.value
    }

    /// Synchronous variant for tests. Production callers should use the async
    /// form which offloads the CPU work.
    static func compressSync(_ original: UIImage, maxDimension: CGFloat = 1024) -> UIImage {
        // Normalize orientation — UIImage from Files can carry EXIF
        // rotation that causes layout jumps when set as view content.
        let normalized: UIImage
        if original.imageOrientation != .up {
            let renderer = UIGraphicsImageRenderer(size: original.size)
            normalized = renderer.image { _ in
                original.draw(in: CGRect(origin: .zero, size: original.size))
            }
        } else {
            normalized = original
        }

        let size = normalized.size
        guard size.width > maxDimension || size.height > maxDimension else {
            return normalized
        }

        let scale = maxDimension / max(size.width, size.height)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
