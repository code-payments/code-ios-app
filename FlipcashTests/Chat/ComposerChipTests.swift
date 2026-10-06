//
//  ComposerChipTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Composer chips")
struct ComposerChipTests {

    private final class BundleToken {}

    private struct Fixture: Decodable {
        let maxAttachments: Int
    }

    private func loadFixture() throws -> Fixture {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "chat_media", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private let uploader = ChatMediaUploader(blob: MockChatMediaBlobStore())

    private func testImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 6), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        }
    }

    @Test("Staging a photo adds a chip that is still preparing")
    func stagingAddsPreparingChip() throws {
        let composer = ComposerModel()
        let chip = try #require(composer.stageChip(image: testImage(), uploader: uploader))

        #expect(composer.chips.map(\.id) == [chip.id])
        #expect(chip.state == .preparing)
        #expect(chip.preparedWidth == nil)
        #expect(chip.preparedHeight == nil)
    }

    @Test("Chips keep the order they were staged in")
    func chipsKeepStagingOrder() throws {
        let composer = ComposerModel()
        let first = try #require(composer.stageChip(image: testImage(), uploader: uploader))
        let second = try #require(composer.stageChip(image: testImage(), uploader: uploader))
        let third = try #require(composer.stageChip(image: testImage(), uploader: uploader))

        #expect(composer.chips.map(\.id) == [first.id, second.id, third.id])
    }

    @Test("Removing a chip drops only that chip")
    func removingDropsOnlyThatChip() throws {
        let composer = ComposerModel()
        let first = try #require(composer.stageChip(image: testImage(), uploader: uploader))
        let second = try #require(composer.stageChip(image: testImage(), uploader: uploader))

        composer.removeChip(first.id)

        #expect(composer.chips.map(\.id) == [second.id])
    }

    @Test("The composer refuses a chip past the fixture's maxAttachments")
    func refusesChipPastMaxAttachments() throws {
        let fixture = try loadFixture()
        #expect(ComposerModel.maxAttachments == fixture.maxAttachments)

        let composer = ComposerModel()
        for _ in 0..<fixture.maxAttachments {
            #expect(composer.stageChip(image: testImage(), uploader: uploader) != nil)
        }

        #expect(composer.stageChip(image: testImage(), uploader: uploader) == nil)
        #expect(composer.chips.count == fixture.maxAttachments)
    }

    @Test("A staged photo with no text can be sent, even while it is still uploading")
    func chipsAloneEnableSend() throws {
        let composer = ComposerModel()
        let chip = try #require(composer.stageChip(image: testImage(), uploader: uploader))

        #expect(chip.state == .preparing)
        #expect(composer.canSubmit)
    }

    @Test("A chip that failed for good holds the send back until it is removed")
    func unretryableChipDisablesSend() throws {
        let composer = ComposerModel()
        composer.draft = "look"
        let chip = try #require(composer.stageChip(image: testImage(), uploader: uploader))
        chip.state = .failed(.notRetryable)

        #expect(!composer.canSubmit)

        composer.removeChip(chip.id)
        #expect(composer.canSubmit)
    }

    @Test("A chip whose upload failed offline can still be sent")
    func retryableChipStillSends() throws {
        let composer = ComposerModel()
        composer.draft = "look"
        let chip = try #require(composer.stageChip(image: testImage(), uploader: uploader))
        chip.state = .failed(.retryable)

        #expect(composer.canSubmit)
        guard case .media(let chips, caption: "look") = composer.outgoing else {
            Issue.record("expected the chip to go out as media")
            return
        }
        #expect(chips.map(\.id) == [chip.id])
    }

    @Test("Clearing after a send empties both the text and the chips")
    func clearEmptiesChips() throws {
        let composer = ComposerModel()
        composer.draft = "look"
        _ = try #require(composer.stageChip(image: testImage(), uploader: uploader))

        composer.clear()

        #expect(composer.draft.isEmpty)
        #expect(composer.chips.isEmpty)
    }
}
