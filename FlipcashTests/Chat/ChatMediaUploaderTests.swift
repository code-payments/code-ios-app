//
//  ChatMediaUploaderTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
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
        }

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

        let blobID = try await ChatMediaUploader(blob: blob, backoff: [.zero]).upload(Self.image(width: 40, height: 30)) { _, _ in }

        #expect(blobID == MockChatMediaBlobStore.blobID)
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

    // MARK: - Chip -

    @Test("A staged chip uploads, with its dimensions set before the bytes are stored")
    func stagedChipUploads() async throws {
        let blob = MockChatMediaBlobStore(policy: Self.policy(maxSizeBytes: 5_000_000, maxEdge: 20))
        let composer = ComposerModel()
        let chip = try #require(composer.stageChip(image: Self.image(width: 40, height: 30), uploader: ChatMediaUploader(blob: blob)))
        var dimensionsAtStore: (Int?, Int?)?
        blob.onStore = { dimensionsAtStore = (chip.preparedWidth, chip.preparedHeight) }

        #expect(chip.state == .preparing)

        let blobID = try await #require(chip.uploadTask).value

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

    @Test("Retrying a failed chip uploads it again")
    func retryingFailedChipUploadsAgain() async throws {
        let blob = MockChatMediaBlobStore()
        blob.finalization = .failure(ErrorBlob.timedOut)
        let uploader = ChatMediaUploader(blob: blob)
        let composer = ComposerModel()
        let chip = try #require(composer.stageChip(image: Self.image(width: 40, height: 30), uploader: uploader))
        _ = await chip.uploadTask?.result
        #expect(chip.state == .failed(.retryable))

        blob.finalization = .success(())
        chip.startUpload(using: uploader)
        let blobID = try await #require(chip.uploadTask).value

        #expect(chip.state == .uploaded(blobID))
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
}
