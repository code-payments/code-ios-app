//
//  ConversationMediaSendTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@MainActor
@Suite("Sending photos")
struct ConversationMediaSendTests {

    private let conversationID = ConversationID.test(1)

    /// Mirrors `ConversationReplySendTests.makeController`.
    private func makeController(_ mock: MockConversations) -> ConversationController {
        ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: try! Database.makeTemp().database,
            owner: .generate()!, selfUserID: UUID(),
            typingHeartbeatInterval: .seconds(3), incomingTypingExpiry: .seconds(10)
        )
    }

    private func testImage(width: CGFloat = 8, height: CGFloat = 6, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func blobID(_ name: String) -> BlobID {
        BlobID(data: Data(name.utf8))
    }

    /// A chip whose upload has already finished with `name`'s blob.
    private func uploadedChip(_ name: String) -> ComposerChip {
        let chip = ComposerChip(image: testImage())
        let blobID = blobID(name)
        chip.uploadTask = Task { blobID }
        return chip
    }

    /// A chip whose upload ends only when the test opens `gate`.
    private func gatedChip(_ gate: UploadGate, image: UIImage? = nil) -> ComposerChip {
        let chip = ComposerChip(image: image ?? testImage())
        chip.uploadTask = Task { try await gate.wait() }
        return chip
    }

    /// Yields the main actor until `condition` holds, so a send started in a `Task` can reach its
    /// first suspension.
    private func yield(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    private func pendingMedia(_ controller: ConversationController) -> [ConversationMessage] {
        controller.messages(for: conversationID).filter {
            switch $0.content {
            case .media:                                    $0.clientMessageID != nil && $0.id == .unassigned
            case .text, .cash, .deleted, .encrypted, .widget: false
            }
        }
    }

    private func attachment(of message: ConversationMessage) -> MediaAttachment? {
        switch message.content {
        case .media(let attachments, _):                attachments.first
        case .text, .cash, .deleted, .encrypted, .widget: nil
        }
    }

    // MARK: - Fan-out

    @Test("Each fanOut vector with chips posts one message per chip, caption last, reply first")
    func fanOutMatchesFixture() async throws {
        for vector in try ChatMediaFanOutVectorTests.loadVectors() where !vector.chips.isEmpty {
            let mock = MockConversations()
            let controller = makeController(mock)

            let sent = await controller.sendMedia(
                vector.chips.map(uploadedChip),
                caption: vector.text,
                to: conversationID,
                repliedTo: vector.replyTo.flatMap { ChatMediaFanOutVectorTests.replyIDs[$0] }
            )

            #expect(sent, "\(vector.name)")
            #expect(mock.sentMedia.count == vector.messages.count, "\(vector.name)")
            for (call, expected) in zip(mock.sentMedia, vector.messages) {
                #expect(expected.kind == "media", "\(vector.name)")
                #expect(call.blobID == blobID(try #require(expected.chip)), "\(vector.name)")
                #expect(call.caption == expected.caption, "\(vector.name)")
                #expect(call.repliedTo == expected.replyTo.flatMap { ChatMediaFanOutVectorTests.replyIDs[$0] }, "\(vector.name)")
            }
            #expect(pendingMedia(controller).isEmpty, "\(vector.name): every row confirmed")
        }
    }

    @Test("Every pending bubble appears before any upload has finished")
    func insertsAllPendingRowsUpFront() async {
        let mock = MockConversations()
        let controller = makeController(mock)
        let first = UploadGate(), second = UploadGate()

        let send = Task { await controller.sendMedia([gatedChip(first), gatedChip(second)], caption: "hi", to: conversationID) }
        await yield { pendingMedia(controller).count == 2 }

        let pending = pendingMedia(controller)
        #expect(pending.count == 2)
        #expect(pending.allSatisfy { $0.status == .sending })
        #expect(pending.map(\.content.mediaCaption) == [nil, "hi"])
        #expect(mock.sentMedia.isEmpty)

        first.open(.success(blobID("a")))
        second.open(.success(blobID("b")))
        #expect(await send.value)
    }

    @Test("A later photo that finishes uploading first still posts second")
    func postsStrictlyInChipOrder() async {
        let mock = MockConversations()
        let controller = makeController(mock)
        let slow = UploadGate()

        let send = Task { await controller.sendMedia([gatedChip(slow), uploadedChip("fast")], caption: nil, to: conversationID) }
        await yield { pendingMedia(controller).count == 2 }
        for _ in 0..<20 { await Task.yield() }
        #expect(mock.sentMedia.isEmpty, "the second photo waits for the first")

        slow.open(.success(blobID("slow")))
        #expect(await send.value)
        #expect(mock.sentMedia.map(\.blobID) == [blobID("slow"), blobID("fast")])
    }

    @Test("A photo that fails to upload fails only its own bubble")
    func failedUploadFailsOnlyItsRow() async throws {
        let mock = MockConversations()
        let controller = makeController(mock)
        let rejected = ComposerChip(image: testImage())
        rejected.uploadTask = Task { throw ChatMediaUploadError.rejected(.moderation) }

        let sent = await controller.sendMedia([rejected, uploadedChip("ok")], caption: nil, to: conversationID)

        #expect(!sent)
        #expect(mock.sentMedia.map(\.blobID) == [blobID("ok")])
        let pending = pendingMedia(controller)
        #expect(pending.count == 1)
        #expect(pending.first?.status == .failed)
        #expect(controller.pendingMediaImage(forMessageID: try #require(pending.first?.stableID)) === rejected.image)
    }

    @Test("A photo the server refuses to post leaves a failed bubble")
    func failedPostFailsTheRow() async {
        let mock = MockConversations()
        mock.mediaSendError = ErrorSendMessage.transportFailure
        let controller = makeController(mock)

        #expect(!(await controller.sendMedia([uploadedChip("a")], caption: "hi", to: conversationID)))

        #expect(pendingMedia(controller).map(\.status) == [.failed])
    }

    // MARK: - Pending bubble

    @Test("The pending bubble carries the upload size once the chip knows it")
    func pendingRowUsesPreparedSize() async {
        let controller = makeController(MockConversations())
        let gate = UploadGate()
        let chip = gatedChip(gate)
        chip.preparedWidth = 2048
        chip.preparedHeight = 1536

        let send = Task { await controller.sendMedia([chip], caption: nil, to: conversationID) }
        await yield { pendingMedia(controller).count == 1 }

        let attachment = pendingMedia(controller).first.flatMap(attachment(of:))
        #expect(attachment?.width == 2048)
        #expect(attachment?.height == 1536)
        #expect(attachment?.blobID == nil)

        gate.open(.success(blobID("a")))
        _ = await send.value
    }

    @Test("A chip still preparing sizes its bubble from the source image's pixels")
    func pendingRowFallsBackToSourcePixels() async {
        let controller = makeController(MockConversations())
        let gate = UploadGate()
        let chip = gatedChip(gate, image: testImage(width: 8, height: 6, scale: 2))

        let send = Task { await controller.sendMedia([chip], caption: nil, to: conversationID) }
        await yield { pendingMedia(controller).count == 1 }

        let attachment = pendingMedia(controller).first.flatMap(attachment(of:))
        #expect(attachment?.width == 16)
        #expect(attachment?.height == 12)

        gate.open(.success(blobID("a")))
        _ = await send.value
    }

    @Test("The local image is served for a pending photo and dropped once it is confirmed")
    func localImageLivesUntilConfirmed() async throws {
        let controller = makeController(MockConversations())
        let gate = UploadGate()
        let chip = gatedChip(gate)

        let send = Task { await controller.sendMedia([chip], caption: nil, to: conversationID) }
        await yield { pendingMedia(controller).count == 1 }
        let messageID = try #require(pendingMedia(controller).first?.stableID)
        #expect(controller.pendingMediaImage(forMessageID: messageID) === chip.image)

        gate.open(.success(blobID("a")))
        _ = await send.value
        #expect(controller.pendingMediaImage(forMessageID: messageID) == nil)
    }

    // MARK: - Retry

    @Test("Retrying a photo whose post failed posts the same blob under the same client id")
    func retryReposts() async throws {
        let mock = MockConversations()
        mock.mediaSendError = ErrorSendMessage.transportFailure
        let controller = makeController(mock)
        _ = await controller.sendMedia([uploadedChip("a")], caption: "hi", to: conversationID, repliedTo: MessageID(value: 7))
        let failed = try #require(pendingMedia(controller).first)
        let clientMessageID = try #require(failed.clientMessageID)

        mock.mediaSendError = nil
        await controller.retry(clientMessageID: clientMessageID, in: conversationID)

        #expect(mock.sentMedia.count == 2)
        let retried = try #require(mock.sentMedia.last)
        #expect(retried.clientMessageID == clientMessageID)
        #expect(retried.blobID == blobID("a"))
        #expect(retried.caption == "hi")
        #expect(retried.repliedTo == MessageID(value: 7))
        #expect(pendingMedia(controller).isEmpty)
    }

    @Test("Retrying a photo whose upload failed uploads it again before posting")
    func retryReuploads() async throws {
        let mock = MockConversations()
        let controller = makeController(mock)
        let blob = MockChatMediaBlobStore()
        blob.storeResults = [.failure(ErrorBlob.uploadDenied)]
        let chip = ComposerChip(image: testImage())
        chip.startUpload(using: ChatMediaUploader(blob: blob, backoff: []))

        #expect(!(await controller.sendMedia([chip], caption: nil, to: conversationID)))
        #expect(chip.state == .failed(.retryable))
        let clientMessageID = try #require(pendingMedia(controller).first?.clientMessageID)

        await controller.retry(clientMessageID: clientMessageID, in: conversationID)

        #expect(blob.storeAttempts == 2)
        #expect(mock.sentMedia.map(\.blobID) == [MockChatMediaBlobStore.blobID])
        #expect(pendingMedia(controller).isEmpty)
    }

    @Test("A photo refused by moderation is not retried")
    func moderationIsNotRetried() async throws {
        let mock = MockConversations()
        let controller = makeController(mock)
        let blob = MockChatMediaBlobStore()
        blob.finalization = .failure(ErrorBlob.rejected(.moderation))
        let chip = ComposerChip(image: testImage())
        chip.startUpload(using: ChatMediaUploader(blob: blob, backoff: []))

        _ = await controller.sendMedia([chip], caption: nil, to: conversationID)
        let clientMessageID = try #require(pendingMedia(controller).first?.clientMessageID)

        await controller.retry(clientMessageID: clientMessageID, in: conversationID)

        #expect(blob.storeAttempts == 1)
        #expect(mock.sentMedia.isEmpty)
        #expect(pendingMedia(controller).map(\.status) == [.failed])
    }
}

/// An upload the test finishes by hand.
@MainActor
private final class UploadGate {

    private var continuation: CheckedContinuation<BlobID, Error>?
    private var result: Result<BlobID, Error>?

    func wait() async throws -> BlobID {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func open(_ result: Result<BlobID, Error>) {
        if let continuation {
            continuation.resume(with: result)
            self.continuation = nil
        } else {
            self.result = result
        }
    }
}

private extension ConversationMessage.Content {
    var mediaCaption: String? {
        switch self {
        case .media(_, let caption):                    caption
        case .text, .cash, .deleted, .encrypted, .widget: nil
        }
    }
}
