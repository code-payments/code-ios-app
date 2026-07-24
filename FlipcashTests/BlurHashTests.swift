//
//  BlurHashTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashUI

@Suite("BlurHash Tests")
struct BlurHashTests {

    /// A valid 4×3-component hash from the BlurHash reference test vectors.
    private let validHash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

    @Test("Decodes a valid hash to an image of the requested size")
    func decodesValidHash() throws {
        let image = try #require(BlurHash.decode(validHash, width: 32, height: 24))
        #expect(image.size == CGSize(width: 32, height: 24))
    }

    @Test("Returns nil for nil or blank hashes")
    func nilForNilOrBlank() {
        #expect(BlurHash.decode(nil, width: 16, height: 16) == nil)
        #expect(BlurHash.decode("", width: 16, height: 16) == nil)
    }

    @Test("Returns nil when the declared component count doesn't match the length")
    func nilForComponentMismatch() {
        // Truncated hash: the size flag promises more components than the string carries.
        let truncated = String(validHash.dropLast(4))
        #expect(BlurHash.decode(truncated, width: 16, height: 16) == nil)
    }

    @Test("Returns nil for non-positive dimensions")
    func nilForNonPositiveDimensions() {
        #expect(BlurHash.decode(validHash, width: 0, height: 16) == nil)
        #expect(BlurHash.decode(validHash, width: 16, height: -1) == nil)
    }

    @Test("Returns nil for characters outside the base-83 alphabet")
    func nilForOutOfAlphabetCharacters() {
        // 'é' is not part of the BlurHash alphabet.
        let invalid = "L" + String(repeating: "é", count: validHash.count - 1)
        #expect(BlurHash.decode(invalid, width: 16, height: 16) == nil)
    }

    @Test("Cache returns nil for a nil or empty hash and decodes otherwise")
    func cacheHandlesAbsentAndValidHashes() throws {
        #expect(BlurHashCache.shared.image(for: nil) == nil)
        #expect(BlurHashCache.shared.image(for: "") == nil)

        let image = try #require(BlurHashCache.shared.image(for: validHash, width: 24, height: 24))
        #expect(image.size == CGSize(width: 24, height: 24))
    }
}
