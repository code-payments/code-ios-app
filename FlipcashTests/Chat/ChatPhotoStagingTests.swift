//
//  ChatPhotoStagingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
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

    @Test("Added photos that are already loaded stage at once, in selection order, handing off the first")
    func addedLoadedStageAtOnce() async {
        let composer = ComposerModel()
        let picked = images(3)

        let added = ChatPhotoStaging.stageAdded(
            Array(picked.indices), into: composer, uploader: uploader,
            loaded: { picked[$0] }, load: { picked[$0] }
        )

        #expect(added.remainder == nil)
        #expect(composer.chips.map(\.image) == picked)
        #expect(added.handOff == composer.chips.first?.id)
    }

    @Test("Added photos still loading stage after the loaded ones without blocking, keeping selection order")
    func addedUnloadedStageLater() async {
        let composer = ComposerModel()
        let picked = images(3)

        let added = ChatPhotoStaging.stageAdded(
            Array(picked.indices), into: composer, uploader: uploader,
            loaded: { $0 == 0 ? picked[0] : nil }, load: { picked[$0] }
        )

        #expect(composer.chips.map(\.image) == [picked[0]])
        #expect(added.handOff == composer.chips.first?.id)
        await added.remainder?.value
        #expect(composer.chips.map(\.image) == picked)
    }

    @Test("When the first added photo is still loading nothing is handed off and nothing waits for it")
    func addedFirstUnloadedHandsOffNothing() async {
        let composer = ComposerModel()
        let picked = images(2)

        let added = ChatPhotoStaging.stageAdded(
            Array(picked.indices), into: composer, uploader: uploader,
            loaded: { $0 == 1 ? picked[1] : nil }, load: { picked[$0] }
        )

        #expect(added.handOff == nil)
        #expect(composer.chips.isEmpty)
        await added.remainder?.value
        // The second, though loaded first, still lands after the first.
        #expect(composer.chips.map(\.image) == picked)
    }

    @Test("Adding stops at a full composer")
    func addedStopsWhenFull() throws {
        let composer = ComposerModel()
        for image in images(ComposerModel.maxAttachments - 1) {
            try #require(composer.stageChip(image: image, uploader: uploader) != nil)
        }
        let picked = images(3)

        let added = ChatPhotoStaging.stageAdded(
            Array(picked.indices), into: composer, uploader: uploader,
            loaded: { picked[$0] }, load: { picked[$0] }
        )

        #expect(added.remainder == nil)
        #expect(composer.chips.count == ComposerModel.maxAttachments)
        #expect(composer.chips.last?.image == picked[0])
    }

    @Test("A photo with a sideways EXIF orientation decodes with the turn drawn into its pixels")
    func decodeBakesOrientation() async throws {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let pixels = try #require(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 3), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        }.cgImage)
        CGImageDestinationAddImage(destination, pixels, [kCGImagePropertyOrientation: CGImagePropertyOrientation.right.rawValue] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let decoded = try #require(await ChatPhotoStaging.decode(data as Data))

        #expect(decoded.imageOrientation == .up)
        #expect(decoded.size == CGSize(width: 3, height: 4))
    }
}

@MainActor
@Suite("Chat photo preloader")
struct ChatPhotoPreloaderTests {

    private static func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { _ in }
    }

    @Test("Selecting starts a load for each new item and keeps what it loads")
    func selectingLoads() async {
        let image = Self.image()
        let preloader = ChatPhotoPreloader<Int> { _ in image }

        preloader.update(selection: [1, 2])
        #expect(preloader.trackedItems == [1, 2])

        #expect(await preloader.image(for: 1) === image)
        #expect(await preloader.image(for: 2) === image)
    }

    @Test("An item already loading is not loaded again")
    func noDuplicateLoads() async {
        var loads: [Int] = []
        let preloader = ChatPhotoPreloader<Int> { item in
            loads.append(item)
            return Self.image()
        }

        preloader.update(selection: [1])
        preloader.update(selection: [1, 2])
        _ = await preloader.image(for: 1)
        _ = await preloader.image(for: 2)

        #expect(loads.sorted() == [1, 2])
    }

    @Test("Deselecting drops the item's load and image")
    func deselectingDrops() async {
        let preloader = ChatPhotoPreloader<Int> { _ in Self.image() }
        preloader.update(selection: [1, 2])
        _ = await preloader.image(for: 1)

        preloader.update(selection: [2])

        #expect(preloader.trackedItems == [2])
        #expect(preloader.loadedImage(for: 1) == nil)
    }

    @Test("Reset cancels every load and lets go of every image")
    func resetClears() async {
        let preloader = ChatPhotoPreloader<Int> { _ in Self.image() }
        preloader.update(selection: [1, 2])
        _ = await preloader.image(for: 1)

        preloader.reset()

        #expect(preloader.trackedItems.isEmpty)
        #expect(preloader.images.isEmpty)
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
@Suite("Attach card")
struct AttachCardTests {

    @Test("A fresh card is down, at the fallback height, and holds no room above the bar")
    func freshCardIsClosed() {
        let card = AttachCard()
        #expect(!card.isOpen)
        #expect(!card.holdsOverflow)
        #expect(card.height == AttachCard.fallbackHeight)
    }

    @Test("The card takes a fixed share of the screen's height", arguments: [
        (CGFloat(874), CGFloat(507)),
        (CGFloat(667), CGFloat(387)),
    ])
    func takesShareOfScreen(screenHeight: CGFloat, expected: CGFloat) {
        let card = AttachCard()
        card.open(.camera, screenHeight: screenHeight)
        #expect(card.height == expected)
    }

    @Test("An unmeasured screen falls back to the fixed height")
    func unmeasuredScreenFallsBack() {
        #expect(AttachCard.height(forScreenHeight: 0) == AttachCard.fallbackHeight)
    }

    @Test("A keyboard rising takes down the card that is up, and its room above the bar", arguments: [
        AttachCard.Content.camera,
        .photos,
    ])
    func keyboardClosesCard(content: AttachCard.Content) {
        let card = AttachCard()
        card.open(content, screenHeight: 874)
        #expect(card.content == content)
        #expect(card.holdsOverflow)

        card.keyboardWillShow()
        #expect(card.content == nil)
        #expect(!card.holdsOverflow)
    }

    @Test("A keyboard rising as a card starts landing on its chip leaves the card up to land")
    func keyboardLeavesLandingAlone() {
        let card = AttachCard()
        let chipID = UUID()
        card.open(.photos, screenHeight: 874)
        card.beginLanding(on: chipID)

        card.keyboardWillShow()
        #expect(card.content == .photos)
        #expect(card.landingChipID == chipID)
    }

    @Test("Over the keyboard, an input view swap announcing the keyboard leaves an opening card alone")
    func keyboardGateHoldsOverKeyboard() {
        let card = AttachCard()
        card.closesOnKeyboardShow = false
        card.open(.camera, screenHeight: 874)
        card.keyboardWillShow()
        #expect(card.content == .camera)
    }

    @Test("The card holds the camera or the photo card, not both")
    func holdsOneContent() {
        let card = AttachCard()
        card.open(.photos, screenHeight: 874)
        card.open(.camera, screenHeight: 874)
        #expect(card.content == .photos)

        card.close()
        card.open(.camera, screenHeight: 874)
        #expect(card.content == .camera)
    }

    @Test("A card back up before the last exit finished keeps its room above the bar")
    func reopenKeepsOverflow() {
        let card = AttachCard()
        card.open(.camera, screenHeight: 874)
        card.close()
        card.open(.photos, screenHeight: 874)
        card.exitDidFinish()
        #expect(card.holdsOverflow)
    }
}

@MainActor
@Suite("Chat camera capture hand-off")
struct ChatCameraCaptureHandOffTests {

    @Test("A capture waits for its chip's frame, then the card shrinks onto it and the chip shows")
    func captureLandsOnChip() {
        let card = AttachCard()
        let chipID = UUID()
        card.open(.camera, screenHeight: 874)

        card.beginLanding(on: chipID)
        #expect(card.isOpen, "The card holds until the chip is laid out")
        #expect(card.landingChipID == chipID)

        let frame = CGRect(x: 20, y: 700, width: 64, height: 64)
        #expect(card.landingChipDidLayout(frame))
        #expect(card.landingChipFrame == frame)

        card.close()
        card.endLanding()
        card.exitDidFinish()
        #expect(card.landingChipID == nil)
        #expect(!card.holdsOverflow)
    }

    @Test("A chip laid out after the card has gone has nothing to land")
    func lateChipLandsNothing() {
        let card = AttachCard()
        card.open(.camera, screenHeight: 874)
        card.beginLanding(on: UUID())
        card.close()
        #expect(!card.landingChipDidLayout(CGRect(x: 0, y: 0, width: 64, height: 64)))
    }

}
