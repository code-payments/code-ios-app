//
//  ChatMediaBubbleVectorTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashUI

@Suite("Chat media bubble vectors")
struct ChatMediaBubbleVectorTests {

    private final class BundleToken {}

    struct Vector: Decodable {
        struct Expected: Decodable {
            let width: Double
            let height: Double
            let cropped: Bool
        }
        let name: String
        let imageWidth: Double
        let imageHeight: Double
        let maxWidth: Double
        let expected: Expected
    }

    private struct Fixture: Decodable {
        let minAspect: Double
        let maxAspect: Double
        let bubble: [Vector]
    }

    private static func loadFixture() throws -> Fixture {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "chat_media", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test("The clamp bounds match the fixture")
    func clampBoundsMatchFixture() throws {
        let fixture = try Self.loadFixture()
        #expect(ChatMediaBubbleSizing.minAspect == fixture.minAspect)
        #expect(ChatMediaBubbleSizing.maxAspect == fixture.maxAspect)
    }

    @Test("The bubble size matches every bubble vector")
    func matchesFixture() throws {
        let vectors = try Self.loadFixture().bubble
        #expect(!vectors.isEmpty)

        for vector in vectors {
            let size = ChatMediaBubbleSizing.size(
                imageWidth: vector.imageWidth,
                imageHeight: vector.imageHeight,
                maxWidth: vector.maxWidth
            )
            #expect(abs(size.width - vector.expected.width) < 0.001, "\(vector.name)")
            #expect(abs(size.height - vector.expected.height) < 0.001, "\(vector.name)")
            #expect(size.cropped == vector.expected.cropped, "\(vector.name)")
        }
    }
}
