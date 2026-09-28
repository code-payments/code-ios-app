//
//  ChatPhotoStagingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Chat photo staging")
struct ChatPhotoStagingTests {

    private let uploader = ChatMediaUploader(blob: MockChatMediaBlobStore())

    private func images(_ count: Int) -> [UIImage] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return (0..<count).map { index in
            UIGraphicsImageRenderer(size: CGSize(width: 4 + index, height: 3), format: format).image { context in
                UIColor.blue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4 + index, height: 3))
            }
        }
    }

    @Test("Picked photos are staged in pick order")
    func stagesInPickOrder() async {
        let composer = ComposerModel()
        let picked = images(3)

        let staged = await ChatPhotoStaging.stage(picked, into: composer, uploader: uploader) { $0 }

        #expect(staged.map(\.id) == composer.chips.map(\.id))
        #expect(composer.chips.map(\.image) == picked)
    }

    @Test("A photo that fails to load is skipped and the rest still stage")
    func skipsPhotoThatFailsToLoad() async {
        let composer = ComposerModel()
        let picked = images(3)

        await ChatPhotoStaging.stage(Array(picked.indices), into: composer, uploader: uploader) { index in
            index == 1 ? nil : picked[index]
        }

        #expect(composer.chips.map(\.image) == [picked[0], picked[2]])
    }

    @Test("Staging stops at the first photo a full composer refuses")
    func stopsAtTheCap() async {
        let composer = ComposerModel()
        let picked = images(ComposerModel.maxAttachments + 2)
        var loads = 0

        await ChatPhotoStaging.stage(picked, into: composer, uploader: uploader) { image in
            loads += 1
            return image
        }

        #expect(composer.chips.map(\.image) == Array(picked.prefix(ComposerModel.maxAttachments)))
        #expect(loads == ComposerModel.maxAttachments + 1)
    }

    @Test("Photos after ones already staged fill only the room left")
    func fillsOnlyTheRoomLeft() async throws {
        let composer = ComposerModel()
        for image in images(ComposerModel.maxAttachments - 1) {
            try #require(composer.stageChip(image: image, uploader: uploader) != nil)
        }
        let picked = images(3)

        let staged = await ChatPhotoStaging.stage(picked, into: composer, uploader: uploader) { $0 }

        #expect(staged.map(\.image) == [picked[0]])
        #expect(composer.chips.count == ComposerModel.maxAttachments)
    }
}

@MainActor
@Suite("Composer outgoing send")
struct ComposerOutgoingTests {

    private let uploader = ChatMediaUploader(blob: MockChatMediaBlobStore())

    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 3), format: format).image { _ in }
    }

    @Test("Text alone sends as text")
    func textAloneSendsText() {
        let composer = ComposerModel()
        composer.draft = "  hello  "

        switch composer.outgoing {
        case .text(let text):
            #expect(text == "hello")
        case .media, .none:
            Issue.record("Expected a text send")
        }
    }

    @Test("Staged photos send as media, captioned with the text")
    func chipsSendAsMediaWithCaption() throws {
        let composer = ComposerModel()
        let first = try #require(composer.stageChip(image: image(), uploader: uploader))
        let second = try #require(composer.stageChip(image: image(), uploader: uploader))
        composer.draft = " look "

        switch composer.outgoing {
        case .media(let chips, let caption):
            #expect(chips.map(\.id) == [first.id, second.id])
            #expect(caption == "look")
        case .text, .none:
            Issue.record("Expected a media send")
        }
    }

    @Test("Staged photos with no text send without a caption")
    func chipsWithoutTextSendWithoutCaption() throws {
        let composer = ComposerModel()
        try #require(composer.stageChip(image: image(), uploader: uploader) != nil)

        switch composer.outgoing {
        case .media(let chips, let caption):
            #expect(chips.count == 1)
            #expect(caption == nil)
        case .text, .none:
            Issue.record("Expected a media send")
        }
    }

    @Test("A reply with staged photos still sends as media")
    func replyWithChipsSendsMedia() throws {
        let composer = ComposerModel()
        composer.beginReplying(to: ComposerModel.ReplyTarget(
            messageID: MessageID(value: 7),
            stableID: "7",
            authorName: "Ana",
            authorID: nil,
            snippet: "hi"
        ))
        try #require(composer.stageChip(image: image(), uploader: uploader) != nil)

        switch composer.outgoing {
        case .media:
            break
        case .text, .none:
            Issue.record("Expected a media send")
        }
    }

    @Test("A failed chip holds the send")
    func failedChipHoldsSend() throws {
        let composer = ComposerModel()
        let chip = try #require(composer.stageChip(image: image(), uploader: uploader))
        chip.uploadTask?.cancel()
        chip.state = .failed(.retryable)
        composer.draft = "caption"

        #expect(composer.outgoing == nil)
    }

    @Test("An empty composer and an edit send nothing")
    func emptyAndEditingSendNothing() {
        let composer = ComposerModel()
        #expect(composer.outgoing == nil)

        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "original")
        composer.draft = "changed"
        #expect(composer.outgoing == nil)
    }
}

@MainActor
@Suite("Chat camera slot")
struct ChatCameraSlotTests {

    @Test("A fresh slot is closed at the fallback height")
    func freshSlotIsClosed() {
        let slot = ChatCameraSlot()
        #expect(!slot.isOpen)
        #expect(slot.height == ChatCameraSlot.fallbackHeight)
    }

    @Test("The slot takes the keyboard's height above the bottom safe area")
    func takesKeyboardHeight() {
        let slot = ChatCameraSlot()
        slot.keyboardWillShow(height: 336, safeAreaBottom: 34)
        #expect(slot.height == 302)
    }

    @Test("A keyboard rising closes the camera")
    func keyboardClosesCamera() {
        let slot = ChatCameraSlot()
        slot.open()
        #expect(slot.isOpen)

        slot.keyboardWillShow(height: 336, safeAreaBottom: 34)
        #expect(!slot.isOpen)
    }

    @Test("A keyboard no taller than the safe area leaves the height alone")
    func ignoresDegenerateKeyboard() {
        let slot = ChatCameraSlot()
        slot.keyboardWillShow(height: 20, safeAreaBottom: 34)
        #expect(slot.height == ChatCameraSlot.fallbackHeight)
    }
}
