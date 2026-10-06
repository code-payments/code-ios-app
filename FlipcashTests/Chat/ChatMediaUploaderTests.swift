//
//  ChatMediaUploaderTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import SharedCore
@testable import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Chat media upload")
struct ChatMediaUploaderTests {

    private final class BundleToken {}

    private struct Fixture: Decodable {
        let uploadMimeType: String
        let jpegQualityLadder: [Double]
    }

    private func loadFixture() throws -> Fixture {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "chat_media", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    // MARK: - Uploader -

    @Test("Uploads as the fixture's MIME type through the fixture's quality ladder")
    func uploadsFixtureMimeType() async throws {
        let fixture = try loadFixture()
        #expect(ChatMediaEncoder.qualityLadder == fixture.jpegQualityLadder)

        let blob = MockChatMediaBlobStore()
        _ = try await ChatMediaUploader(blob: blob).upload(Self.image(width: 40, height: 30)) { _, _ in }

        #expect(blob.storedMimeTypes == [fixture.uploadMimeType])
    }

    @Test("Reports the downscale target before storing, then awaits finalization")
    func reportsDimensionsBeforeStoring() async throws {
        let blob = MockChatMediaBlobStore(policy: Self.policy(maxSizeBytes: 5_000_000, maxEdge: 2048))
        var prepared: (width: Int, height: Int, storesSoFar: Int)?

        let blobID = try await ChatMediaUploader(blob: blob).upload(Self.image(width: 3000, height: 2000)) { width, height in
            prepared = (width, height, blob.storedData.count)
        }.blobID

        #expect(prepared?.width == 2048)
        #expect(prepared?.height == 1365)
        #expect(prepared?.storesSoFar == 0)
        #expect(blobID == MockChatMediaBlobStore.blobID)
        #expect(blob.finalizedBlobIDs == [blobID])

        let stored = try #require(blob.storedData.first)
        #expect(stored.count <= 5_000_000)
        let decoded = try #require(UIImage(data: stored)?.cgImage)
        #expect(decoded.width == 2048)
        #expect(decoded.height == 1365)
    }

    @Test("A sideways capture is downscaled in display space")
    func sidewaysCaptureUsesDisplaySpace() async throws {
        let landscape = try #require(Self.image(width: 300, height: 200).cgImage)
        let portrait = UIImage(cgImage: landscape, scale: 1, orientation: .right)
        let blob = MockChatMediaBlobStore(policy: Self.policy(maxSizeBytes: 5_000_000, maxEdge: 150))
        var prepared: (width: Int, height: Int)?

        _ = try await ChatMediaUploader(blob: blob).upload(portrait) { prepared = ($0, $1) }

        #expect(prepared?.width == 100)
        #expect(prepared?.height == 150)
        let stored = try #require(blob.storedData.first)
        let decoded = try #require(UIImage(data: stored)?.cgImage)
        #expect(decoded.width == 100)
        #expect(decoded.height == 150)
    }

    @Test("A moderation rejection at finalization is not retryable")
    func moderationRejectionIsTerminal() async {
        let blob = MockChatMediaBlobStore()
        blob.finalization = .failure(ErrorBlob.rejected(.moderation))

        let error = await Self.uploadError(ChatMediaUploader(blob: blob))

        #expect(error?.isRetryable == false)
        #expect(blob.storedData.count == 1)
    }

    @Test("A rejection when storing is not retried automatically")
    func storeRejectionIsNotRetried() async {
        let blob = MockChatMediaBlobStore()
        blob.storeResults = [.failure(ErrorBlob.rejected(.moderation))]

        let error = await Self.uploadError(ChatMediaUploader(blob: blob, backoff: [.zero, .zero]))

        #expect(error?.isRetryable == false)
        #expect(blob.storeAttempts == 1)
        #expect(blob.finalizedBlobIDs.isEmpty)
    }

    @Test("A network failure is retried through the backoff, then surfaces as retryable")
    func networkFailureRetriesThenIsRetryable() async {
        let blob = MockChatMediaBlobStore()
        blob.storeResults = Array(repeating: .failure(ErrorBlob.network(URLError(.networkConnectionLost))), count: 3)

        let error = await Self.uploadError(ChatMediaUploader(blob: blob, backoff: [.zero, .zero]))

        #expect(error?.isRetryable == true)
        #expect(blob.storeAttempts == 3)
    }

    @Test("A network failure that clears within the backoff uploads normally")
    func networkFailureRecovers() async throws {
        let blob = MockChatMediaBlobStore()
        blob.storeResults = [.failure(ErrorBlob.network(URLError(.timedOut)))]

        let photo = try await ChatMediaUploader(blob: blob, backoff: [.zero]).upload(Self.image(width: 40, height: 30)) { _, _ in }

        #expect(photo == .plain(MockChatMediaBlobStore.blobID))
        #expect(blob.storeAttempts == 2)
    }

    @Test("A finalization timeout is retryable")
    func finalizationTimeoutIsRetryable() async {
        let blob = MockChatMediaBlobStore()
        blob.finalization = .failure(ErrorBlob.timedOut)

        let error = await Self.uploadError(ChatMediaUploader(blob: blob))

        #expect(error?.isRetryable == true)
    }

    @Test("A policy with no constraint for JPEG uploads nothing")
    func noMatchingConstraintUploadsNothing() async {
        let policy = UploadPolicy(version: "v1", ttl: nil, constraints: [
            .init(pattern: "video/*", maxSizeBytes: 5_000_000, image: nil),
        ])
        let blob = MockChatMediaBlobStore(policy: policy)

        let error = await Self.uploadError(ChatMediaUploader(blob: blob))

        #expect(error?.isRetryable == false)
        #expect(blob.storeAttempts == 0)
    }

    // MARK: - Encrypted -

    private static func seal() throws -> ChatSeal {
        try ChatSeal(
            cipher: DefaultChatCipher.shared,
            owner: KeyPair.generate()!,
            peerPublicKey: KeyPair.generate()!.publicKey,
            conversationID: ConversationID(data: Data(repeating: 0x07, count: 32)),
            selfUserID: UUID()
        )
    }

    @Test("In a chat that encrypts, the photo is sealed for it within the encrypted ceiling, with its blurhash")
    func encryptedChatSealsPhoto() async throws {
        let policy = UploadPolicy(version: "v1", ttl: nil, constraints: [
            .init(pattern: "image/*", maxSizeBytes: 5_000_000, image: .init(maxWidth: 4096, maxHeight: 4096, maxPixels: 0)),
        ], encrypted: .init(maxSizeBytes: 2_000_000, image: .init(maxWidth: 1000, maxHeight: 1000, maxPixels: 0)))
        let blob = MockChatMediaBlobStore(policy: policy)
        let seal = try Self.seal()
        var uploader = ChatMediaUploader(blob: blob)
        uploader.seal = { seal }

        let photo = try await uploader.upload(Self.image(width: 3000, height: 2000)) { _, _ in }

        guard case .sealed(let sealed) = photo else {
            Issue.record("Expected a sealed photo")
            return
        }
        #expect(blob.storedData.isEmpty)
        #expect(blob.encryptedStores.count == 1)
        #expect(blob.encryptedStores.first?.conversationID == seal.conversationID)
        #expect(sealed.width == 1000)
        #expect((666...667).contains(sealed.height))
        #expect(sealed.mimeType == "image/jpeg")
        #expect(sealed.sizeBytes == blob.encryptedStores.first?.image.count)
        #expect(!sealed.blurhash.isEmpty && sealed.blurhash.count <= 64)
        #expect(blob.finalizedBlobIDs == [sealed.blobID])
    }

    @Test("A chat that encrypts under a policy with no encrypted constraints uploads nothing, for good")
    func encryptedChatWithoutPolicyUploadsNothing() async throws {
        let blob = MockChatMediaBlobStore()
        let seal = try Self.seal()
        var uploader = ChatMediaUploader(blob: blob)
        uploader.seal = { seal }

        let error = await Self.uploadError(uploader)

        #expect(error?.isRetryable == false)
        #expect(blob.storeAttempts == 0)
    }

    @Test("A missing peer key uploads nothing and stays retryable; it never falls back to plaintext")
    func missingPeerKeyUploadsNothing() async {
        let blob = MockChatMediaBlobStore()
        var uploader = ChatMediaUploader(blob: blob)
        uploader.seal = { throw PeerKeyUnavailable(userID: UUID()) }

        let error = await Self.uploadError(uploader)

        #expect(error?.isRetryable == true)
        #expect(blob.storeAttempts == 0)
    }

    @Test("A chat that couldn't be fetched offline leaves the photo retryable, and reports nothing")
    func offlineChatFetchIsRetryable() async {
        let blob = MockChatMediaBlobStore()
        var uploader = ChatMediaUploader(blob: blob)
        uploader.seal = { throw ErrorGetChat.transportFailure }

        let error = await Self.uploadError(uploader)

        #expect(error?.isRetryable == true)
        #expect(error?.isTerminal == false)
        #expect(error?.reportingLevel == .suppressed)
        #expect(blob.storeAttempts == 0)
    }

    @Test("A chat the server refuses to return leaves the photo unretryable")
    func deniedChatFetchIsNotRetryable() async {
        var uploader = ChatMediaUploader(blob: MockChatMediaBlobStore())
        uploader.seal = { throw ErrorGetChat.denied }

        let error = await Self.uploadError(uploader)

        #expect(error?.isRetryable == false)
    }

    // MARK: - Gate -

    @Test("Camera and Photos show in an encrypted DM, a plaintext chat, and not before the chat loads")
    func gateShowsPhotosInEncryptedDMs() {
        let encrypted = Conversation(
            id: ConversationID(data: Data(repeating: 0x01, count: 32)),
            members: [ConversationMember(userID: UUID(), displayName: "A"), ConversationMember(userID: UUID(), displayName: "B")],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: .contactDm,
            useE2Ee: true
        )
        #expect(E2eePolicy.shouldEncrypt(encrypted))
        #expect(ChatMediaGate.acceptsMedia(encrypted))

        var plain = encrypted
        plain.useE2Ee = false
        #expect(ChatMediaGate.acceptsMedia(plain))
        #expect(!ChatMediaGate.acceptsMedia(nil))
    }

    // MARK: - Chip -

    @Test("A staged chip uploads, with its dimensions set before the bytes are stored")
    func stagedChipUploads() async throws {
        let blob = MockChatMediaBlobStore(policy: Self.policy(maxSizeBytes: 5_000_000, maxEdge: 20))
        let composer = ComposerModel()
        let chip = try #require(composer.stageChip(image: Self.image(width: 40, height: 30), uploader: ChatMediaUploader(blob: blob)))
        var dimensionsAtStore: (Int?, Int?)?
        blob.onStore = { dimensionsAtStore = (chip.preparedWidth, chip.preparedHeight) }

        #expect(chip.state == .preparing)

        let blobID = try await #require(chip.uploadTask).value.blobID

        #expect(dimensionsAtStore?.0 == 20)
        #expect(dimensionsAtStore?.1 == 15)
        #expect(chip.state == .uploaded(blobID))
    }

    @Test("A moderated chip fails for good")
    func moderatedChipFailsForGood() async throws {
        let blob = MockChatMediaBlobStore()
        blob.finalization = .failure(ErrorBlob.rejected(.moderation))
        let composer = ComposerModel()
        let chip = try #require(composer.stageChip(image: Self.image(width: 40, height: 30), uploader: ChatMediaUploader(blob: blob)))

        _ = await chip.uploadTask?.result

        #expect(chip.state == .failed(.notRetryable))
    }

    /// The bytes were stored before the wait failed, which is how a send interrupted by the app
    /// going to the background fails; storing them again would leave an orphan blob.
    @Test("Retrying a chip whose wait for the server failed waits again without storing again")
    func retryingFailedChipResumesStoredBlob() async throws {
        let blob = MockChatMediaBlobStore()
        blob.finalization = .failure(ErrorBlob.timedOut)
        let uploader = ChatMediaUploader(blob: blob)
        let composer = ComposerModel()
        let chip = try #require(composer.stageChip(image: Self.image(width: 40, height: 30), uploader: uploader))
        _ = await chip.uploadTask?.result
        #expect(chip.state == .failed(.retryable))

        blob.finalization = .success(())
        chip.startUpload(using: uploader)
        let blobID = try await #require(chip.uploadTask).value.blobID

        #expect(chip.state == .uploaded(blobID))
        #expect(blob.storeAttempts == 1)
        #expect(blob.finalizedBlobIDs == [blobID])
    }

    @Test("A chip's progress follows its bytes, then waits on the server's processing once stored")
    func chipProgressReachesProcessing() async throws {
        let blob = MockChatMediaBlobStore()
        blob.progressReports = [
            BlobUploadProgress(sentBytes: 50, totalBytes: 100),
            BlobUploadProgress(sentBytes: 100, totalBytes: 100),
        ]
        let composer = ComposerModel()
        let chip = try #require(composer.stageChip(image: Self.image(width: 40, height: 30), uploader: ChatMediaUploader(blob: blob)))
        #expect(chip.progress.phase == .preparing)

        _ = try await #require(chip.uploadTask).value

        #expect(chip.progress.phase == .processing)
        #expect(chip.progress.showsOverlay)
    }

    @Test("A chip whose upload fails hands its progress to the failed state; retrying starts it over")
    func chipProgressFailsAndRetries() async throws {
        let blob = MockChatMediaBlobStore()
        blob.finalization = .failure(ErrorBlob.timedOut)
        let uploader = ChatMediaUploader(blob: blob)
        let composer = ComposerModel()
        let chip = try #require(composer.stageChip(image: Self.image(width: 40, height: 30), uploader: uploader))
        _ = await chip.uploadTask?.result
        #expect(chip.progress.phase == .failed)
        #expect(!chip.progress.showsOverlay)

        blob.finalization = .success(())
        chip.startUpload(using: uploader)
        #expect(chip.progress.phase == .preparing)
        _ = try await #require(chip.uploadTask).value
        #expect(chip.progress.phase == .processing)
    }

        @Test("Removing a chip cancels its upload")
    func removingChipCancelsUpload() throws {
        let composer = ComposerModel()
        let chip = try #require(composer.stageChip(image: Self.image(width: 40, height: 30), uploader: ChatMediaUploader(blob: MockChatMediaBlobStore())))

        composer.removeChip(chip.id)

        #expect(composer.chips.isEmpty)
        #expect(chip.uploadTask?.isCancelled == true)
    }

    // MARK: - Helpers -

    private static func image(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func policy(maxSizeBytes: Int, maxEdge: Int) -> UploadPolicy {
        UploadPolicy(version: "v1", ttl: nil, constraints: [
            .init(
                pattern: "image/*",
                maxSizeBytes: maxSizeBytes,
                image: .init(maxWidth: maxEdge, maxHeight: maxEdge, maxPixels: 0)
            ),
        ])
    }

    private static func uploadError(_ uploader: ChatMediaUploader) async -> ChatMediaUploadError? {
        do {
            _ = try await uploader.upload(image(width: 40, height: 30)) { _, _ in }
            return nil
        } catch {
            return error as? ChatMediaUploadError
        }
    }

    @Test("A refused photo reports as an expected outcome, a client defect as an error")
    func reportingLevels() {
        #expect(ChatMediaUploadError.rejected(.moderation).reportingLevel == .info)
        #expect(ChatMediaUploadError.noMatchingConstraint.reportingLevel == .error)
        #expect(ChatMediaUploadError.failed(ErrorBlob.quotaExceeded).reportingLevel == .info)
        #expect(ChatMediaUploadError.failed(ErrorBlob.unknown).reportingLevel == .error)
    }

    @Test("A photo goes out only under the encryption choice it was uploaded for")
    func photoSendMatchesSeal() throws {
        let seal = try Self.seal()
        let chat = seal.conversationID
        let other = ConversationID(data: Data(repeating: 0x08, count: 32))
        let blobID = BlobID(data: Data([1]))
        let sealed = SealedPhoto(blobID: blobID, mimeType: "image/jpeg", sizeBytes: 10, width: 1, height: 1, blurhash: "00")

        #expect(EncryptedChatClient.photoSend(.plain(blobID), seal: nil, conversationID: chat) == .plain(blobID))
        #expect(EncryptedChatClient.photoSend(.sealed(sealed), seal: seal, conversationID: chat) == .sealed(sealed, seal))
        // The chat started encrypting after the photo uploaded in plaintext.
        #expect(EncryptedChatClient.photoSend(.plain(blobID), seal: seal, conversationID: chat) == .mismatch)
        // The chat stopped encrypting after the photo uploaded sealed.
        #expect(EncryptedChatClient.photoSend(.sealed(sealed), seal: nil, conversationID: chat) == .mismatch)
        // A seal for a different chat.
        #expect(EncryptedChatClient.photoSend(.sealed(sealed), seal: seal, conversationID: other) == .mismatch)
    }
}
