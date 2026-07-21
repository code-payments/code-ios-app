//
//  ProfileCreationStateTests.swift
//  FlipcashTests
//

import UIKit
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Profile Creation State Tests")
struct ProfileCreationStateTests {

    /// The bytes are already stored, so resuming must poll the same blob rather
    /// than reserve and upload a second copy.
    @Test("A timed-out attempt resumes the same blob instead of re-storing")
    func timeoutResumesTheSameBlob() async throws {
        let uploader = StubUploader()
        await uploader.setFinalizationResult(.failure(ErrorBlob.timedOut))

        let state = try await makeState()

        await #expect(throws: ErrorBlob.self) {
            try await state.uploadPhoto(with: uploader)
        }
        #expect(await uploader.storeCount == 1)
        #expect(state.reservedBlobID != nil)

        await uploader.setFinalizationResult(.success(()))
        try await state.uploadPhoto(with: uploader)

        #expect(await uploader.storeCount == 1)
        #expect(await uploader.setPictureCount == 1)
    }

    /// Rejection is terminal: the bytes behind a blob are immutable, so the id
    /// can never become ready and the next attempt has to store fresh bytes.
    @Test("A rejection clears the blob so the next attempt re-stores")
    func rejectionForcesAFreshUpload() async throws {
        let uploader = StubUploader()
        await uploader.setFinalizationResult(.failure(ErrorBlob.rejected(.moderation)))

        let state = try await makeState()

        await #expect(throws: ErrorBlob.self) {
            try await state.uploadPhoto(with: uploader)
        }
        #expect(state.reservedBlobID == nil)

        await uploader.setFinalizationResult(.success(()))
        try await state.uploadPhoto(with: uploader)

        #expect(await uploader.storeCount == 2)
    }

    /// A reservation is signed against one byte count, so a different photo can
    /// never be finalized against the previous photo's blob.
    @Test("Choosing a different photo drops the reserved blob")
    func selectingANewPhotoDropsTheReservation() async throws {
        let uploader = StubUploader()
        await uploader.setFinalizationResult(.failure(ErrorBlob.timedOut))

        let state = try await makeState()

        await #expect(throws: ErrorBlob.self) {
            try await state.uploadPhoto(with: uploader)
        }
        #expect(state.reservedBlobID != nil)

        let previous = state.selectedImage
        state.select(Self.image(side: 8))
        try await waitForSelection(on: state, replacing: previous)

        #expect(state.reservedBlobID == nil)
    }

    @Test("A successful upload attaches the picture and releases the bitmap")
    func successAttachesAndReleases() async throws {
        let uploader = StubUploader()
        let state = try await makeState()

        try await state.uploadPhoto(with: uploader)

        #expect(await uploader.setPictureCount == 1)
        #expect(await uploader.refreshCount == 1)
        #expect(state.selectedImage == nil)
        #expect(state.isUploading == false)
    }

    @Test("Uploading without a photo fails before reserving anything")
    func uploadingWithoutAPhotoDoesNotReserve() async throws {
        let uploader = StubUploader()
        let state = ProfileCreationState()

        await #expect(throws: ErrorBlob.self) {
            try await state.uploadPhoto(with: uploader)
        }
        #expect(await uploader.storeCount == 0)
    }

    // MARK: - Helpers -

    private func makeState() async throws -> ProfileCreationState {
        let state = ProfileCreationState()
        state.select(Self.image(side: 4))
        try await waitForSelection(on: state)
        return state
    }

    /// `select` compresses off the main actor, so the selection lands a turn or
    /// more later. Waits for it to differ from `previous` rather than merely be
    /// non-nil, so replacing a photo isn't satisfied by the one already there.
    private func waitForSelection(
        on state: ProfileCreationState,
        replacing previous: UIImage? = nil
    ) async throws {
        for _ in 0..<200 where state.selectedImage === previous {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(state.selectedImage !== previous)
    }

    private static func image(side: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}

// MARK: - Doubles -

/// Counts each leg of the upload and lets a test choose how finalization ends.
private actor StubUploader: ProfilePictureUploading {

    private(set) var storeCount = 0
    private(set) var setPictureCount = 0
    private(set) var refreshCount = 0

    private var finalization: Result<Void, Error> = .success(())
    private var nextBlobSeed: UInt8 = 1

    func setFinalizationResult(_ result: Result<Void, Error>) {
        finalization = result
    }

    func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID {
        storeCount += 1
        defer { nextBlobSeed += 1 }
        return BlobID(data: Data(repeating: nextBlobSeed, count: 16))
    }

    func awaitBlobFinalization(blobID: BlobID) async throws {
        try finalization.get()
    }

    func setProfilePicture(blobID: BlobID) async throws {
        setPictureCount += 1
    }

    func refreshProfile() async throws {
        refreshCount += 1
    }
}
