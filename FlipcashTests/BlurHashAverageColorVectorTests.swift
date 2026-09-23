//
//  BlurHashAverageColorVectorTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import FlipcashUI

/// `test-vectors/blurhash_average.json`. Synced copy — a failure is fixed in the canonical fixture
/// and re-synced to both platforms, never edited here.
///
/// The group invite link card tints its band with this colour, so both apps must read the same
/// colour from the same hash.
@Suite("BlurHash average colour vectors")
struct BlurHashAverageColorVectorTests {

    private final class BundleToken {}

    struct Average: Decodable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    struct Vector: Decodable {
        let name: String
        let blurHash: String
        let average: Average?
    }

    struct Fixture: Decodable {
        let algorithm: String
        let vectors: [Vector]
    }

    private func loadFixture() throws -> Fixture {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "blurhash_average", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test("Every vector reads the expected average colour")
    func vectors() throws {
        let fixture = try loadFixture()
        #expect(fixture.algorithm == "blurhash-average-color")
        #expect(!fixture.vectors.isEmpty)

        for vector in fixture.vectors {
            let expected = vector.average.map { BlurHash.RGB(red: $0.red, green: $0.green, blue: $0.blue) }
            #expect(BlurHash.averageColor(blurHash: vector.blurHash) == expected, "\(vector.name)")
        }
    }

    @Test("A missing hash has no average colour")
    func nilHash() {
        #expect(BlurHash.averageColor(blurHash: nil) == nil)
    }
}
