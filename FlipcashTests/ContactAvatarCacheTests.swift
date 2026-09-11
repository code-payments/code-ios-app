//
//  ContactAvatarCacheTests.swift
//  FlipcashTests
//

import Testing
import UIKit
import FlipcashUI

@Suite("ContactAvatarCache")
struct ContactAvatarCacheTests {

    /// A PNG exactly `side` pixels square. `scale = 1` so the decoded image's `size` is the number
    /// asked for: the renderer otherwise draws at the screen's scale, and `UIImage(data:)` reads a
    /// PNG back at scale 1, which turns an 8pt request into a 24pt image on a 3x device.
    private func png(side: Int) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.pngData()!
    }

    @Test("Decodes and caches the bytes it is given")
    func decodesBytes() {
        let image = ContactAvatarCache.shared.image(forKey: UUID().uuidString, data: png(side: 4))

        #expect(image?.size == CGSize(width: 4, height: 4))
    }

    @Test("Returns nil for bytes that are not an image")
    func rejectsGarbage() {
        #expect(ContactAvatarCache.shared.image(forKey: UUID().uuidString, data: Data([0, 1, 2])) == nil)
    }

    /// The key is the contact's id, which survives the contact changing their picture. Serving the
    /// entry cached under it without checking the bytes leaves the old photo on screen for the rest
    /// of the process — every avatar surface in the app reads through this cache.
    @Test("New bytes under an existing key replace the cached image")
    func newBytesUnderSameKeyReplaceTheImage() {
        let key = UUID().uuidString

        _ = ContactAvatarCache.shared.image(forKey: key, data: png(side: 4))
        let updated = ContactAvatarCache.shared.image(forKey: key, data: png(side: 8))

        #expect(updated?.size == CGSize(width: 8, height: 8))
    }

    @Test("Unchanged bytes under an existing key reuse the decoded image")
    func unchangedBytesReuseTheDecodedImage() {
        let key = UUID().uuidString
        let data = png(side: 4)

        let first = ContactAvatarCache.shared.image(forKey: key, data: data)
        let second = ContactAvatarCache.shared.image(forKey: key, data: data)

        #expect(first === second)
    }
}
