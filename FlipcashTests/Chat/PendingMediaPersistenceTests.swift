//
//  PendingMediaPersistenceTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import UIKit
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@MainActor
@Suite("Pending photo persistence")
struct PendingMediaPersistenceTests {

    private let owner = try! PublicKey(Data(repeating: 7, count: 32))
    private let conversationID = ConversationID.test(1)
    private let selfUserID = UUID()

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pending-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func jpeg() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 6), format: format).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        }
    }

    private func blobID(_ name: String) -> BlobID { BlobID(data: Data(name.utf8)) }

    private func entry(stored: UploadedPhoto? = nil, caption: String? = nil, createdAt: Date = .now) -> PendingMediaStore.Entry {
        .init(clientMessageID: UUID(), conversationID: conversationID, createdAt: createdAt, caption: caption, replyTo: MessageID(value: 9), stored: stored)
    }

    private func makeController(
        _ mock: MockConversations,
        database: Database,
        store: PendingMediaStore,
        blob: MockChatMediaBlobStore
    ) -> ConversationController {
        let controller = ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: selfUserID,
            typingHeartbeatInterval: .seconds(3), incomingTypingExpiry: .seconds(10)
        )
        controller.pendingMedia = store
        controller.restoredPhotoUploader = { _ in ChatMediaUploader(blob: blob) }
        return controller
    }

    private func pendingRows(_ controller: ConversationController) -> [ConversationMessage] {
        controller.messages(for: conversationID).filter { $0.clientMessageID != nil && $0.id == .unassigned }
    }

    private func yield(until condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            await Task.yield()
        }
    }

    // MARK: - Store

    @Test("Entries, their photo and their stored state survive a new store over the same directory")
    func roundTrips() throws {
        let directory = try makeDirectory()
        let store = PendingMediaStore(directory: directory, owner: owner)
        let plain = entry(stored: .plain(blobID("a")), caption: "hi")
        let sealed = entry(stored: .sealed(SealedPhoto(blobID: blobID("b"), mimeType: "image/jpeg", sizeBytes: 10, width: 8, height: 6, blurhash: "LEHV6n")))
        let bare = entry()
        for item in [plain, sealed, bare] {
            store.add(item)
            store.writeImage(jpeg(), for: item.clientMessageID)
        }
        store.setStored(.plain(blobID("c")), for: bare.clientMessageID)

        let reloaded = PendingMediaStore(directory: directory, owner: owner)

        #expect(reloaded.entries.map(\.clientMessageID) == [plain, sealed, bare].map(\.clientMessageID))
        #expect(reloaded.entries[0].caption == "hi")
        #expect(reloaded.entries[0].replyTo == MessageID(value: 9))
        #expect(reloaded.entries[0].chatID == conversationID)
        #expect(reloaded.entries[1].stored == sealed.stored)
        #expect(reloaded.entries[2].stored == .plain(blobID("c")))
        #expect(reloaded.imageData(for: reloaded.entries[0]) == store.imageData(for: plain))
    }

    @Test("Another owner's store does not see the entries")
    func ownerScoped() throws {
        let directory = try makeDirectory()
        let store = PendingMediaStore(directory: directory, owner: owner)
        store.add(entry())

        let other = PendingMediaStore(directory: directory, owner: try PublicKey(Data(repeating: 8, count: 32)))

        #expect(other.entries.isEmpty)
    }

    @Test("Removing an entry deletes its photo")
    func removeDeletesFile() throws {
        let store = PendingMediaStore(directory: try makeDirectory(), owner: owner)
        let item = entry()
        store.add(item)
        store.writeImage(jpeg(), for: item.clientMessageID)

        store.remove(clientMessageID: item.clientMessageID)

        #expect(store.entries.isEmpty)
        #expect(store.imageData(for: item) == nil)
    }

    @Test("Sweeping drops an entry with no photo and a photo with no entry")
    func sweepsOrphans() throws {
        let directory = try makeDirectory()
        let store = PendingMediaStore(directory: directory, owner: owner)
        let kept = entry()
        let noFile = entry()
        store.add(kept)
        store.writeImage(jpeg(), for: kept.clientMessageID)
        store.add(noFile)
        let orphan = directory
            .appendingPathComponent("flipcash-\(owner.base58)-pending-media")
            .appendingPathComponent("\(UUID().uuidString).jpg")
        try jpeg().write(to: orphan)

        store.sweepOrphans()

        #expect(store.entries.map(\.clientMessageID) == [kept.clientMessageID])
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(PendingMediaStore(directory: directory, owner: owner).entries.count == 1)
    }

    @Test("A manifest that cannot be read is an empty store")
    func unreadableManifestIsEmpty() throws {
        let directory = try makeDirectory()
        try Data("not json".utf8).write(to: directory.appendingPathComponent("flipcash-\(owner.base58)-pending-media.json"))

        #expect(PendingMediaStore(directory: directory, owner: owner).entries.isEmpty)
    }

    // MARK: - Restore

    @Test("A send whose bytes never landed comes back as a failed, retryable row")
    func unstoredEntryRestoresFailed() async throws {
        let store = PendingMediaStore(directory: try makeDirectory(), owner: owner)
        let item = entry(caption: "hi")
        store.add(item)
        let bytes = jpeg()
        store.writeImage(bytes, for: item.clientMessageID)
        let mock = MockConversations()
        let blob = MockChatMediaBlobStore()
        let controller = makeController(mock, database: try Database.makeTemp().database, store: store, blob: blob)

        controller.restorePendingMedia()

        let rows = pendingRows(controller)
        #expect(rows.map(\.status) == [.failed])
        #expect(rows.first?.clientMessageID == item.clientMessageID)
        if case .media(_, let caption) = try #require(rows.first).content {
            #expect(caption == "hi")
        } else {
            Issue.record("expected a media row")
        }
        #expect(rows.first?.repliedTo == MessageID(value: 9))
        #expect(controller.pendingMediaImage(forMessageID: try #require(rows.first?.stableID)) != nil)
        #expect(blob.storeAttempts == 0)

        // Retrying uploads the held bytes as they are.
        await controller.retry(clientMessageID: item.clientMessageID, in: conversationID)

        #expect(blob.storedData == [bytes])
        #expect(mock.sentMedia.count == 1)
        #expect(mock.sentMedia.first?.clientMessageID == item.clientMessageID)
        #expect(pendingRows(controller).isEmpty)
        #expect(store.entries.isEmpty, "confirmed sends leave the store")
    }

    @Test("A send whose bytes had landed resumes and posts without storing again")
    func storedEntryResumes() async throws {
        let store = PendingMediaStore(directory: try makeDirectory(), owner: owner)
        let item = entry(stored: .plain(blobID("landed")))
        store.add(item)
        store.writeImage(jpeg(), for: item.clientMessageID)
        let mock = MockConversations()
        let blob = MockChatMediaBlobStore()
        let controller = makeController(mock, database: try Database.makeTemp().database, store: store, blob: blob)

        controller.restorePendingMedia()
        #expect(pendingRows(controller).map(\.status) == [.sending])
        await yield { !mock.sentMedia.isEmpty && store.entries.isEmpty }

        #expect(mock.sentMedia.map(\.blobID) == [blobID("landed")])
        #expect(blob.storeAttempts == 0)
        #expect(blob.finalizedBlobIDs == [blobID("landed")])
        #expect(store.entries.isEmpty)
        #expect(pendingRows(controller).isEmpty)
    }

    @Test("An entry whose blob is already in a message this user sent is dropped; one whose blob is not is kept")
    func reconcilesAgainstLoadedMessages() async throws {
        let store = PendingMediaStore(directory: try makeDirectory(), owner: owner)
        let sent = entry(stored: .plain(blobID("sent")))
        let unsent = entry(stored: .plain(blobID("unsent")))
        for item in [sent, unsent] {
            store.add(item)
            store.writeImage(jpeg(), for: item.clientMessageID)
        }
        let database = try Database.makeTemp().database
        let message = ConversationMessage(
            id: MessageID(value: 5),
            senderID: selfUserID,
            content: .media([MediaAttachment(blobID: blobID("sent"), width: 8, height: 6, blurhash: nil)], caption: nil),
            date: .now,
            unreadSeq: 0,
            repliedTo: nil,
            status: .sent,
            clientMessageID: nil
        )
        try database.upsertConversationMessages([message], conversationID: conversationID)
        let mock = MockConversations()
        mock.mediaSendError = ErrorSendMessage.transportFailure
        let controller = makeController(mock, database: database, store: store, blob: MockChatMediaBlobStore())

        controller.restorePendingMedia()
        await yield { pendingRows(controller).first?.status == .failed }

        #expect(store.entries.map(\.clientMessageID) == [unsent.clientMessageID])
        #expect(pendingRows(controller).map(\.clientMessageID) == [unsent.clientMessageID])
        #expect(mock.sentMedia.map(\.blobID) == [blobID("unsent")], "the already-sent photo is never posted again")
    }

    @Test("A photo the server refuses for good leaves the store")
    func rejectedUploadLeavesStore() async throws {
        let store = PendingMediaStore(directory: try makeDirectory(), owner: owner)
        let item = entry(stored: .plain(blobID("bad")))
        store.add(item)
        store.writeImage(jpeg(), for: item.clientMessageID)
        let blob = MockChatMediaBlobStore()
        blob.finalization = .failure(ErrorBlob.rejected(.moderation))
        let controller = makeController(MockConversations(), database: try Database.makeTemp().database, store: store, blob: blob)

        controller.restorePendingMedia()
        await yield { store.entries.isEmpty }

        #expect(store.entries.isEmpty)
        #expect(pendingRows(controller).map(\.status) == [.failed])
    }

    @Test("A photo sent through the controller is held until its post is confirmed")
    func sendKeepsEntryUntilConfirmed() async throws {
        let store = PendingMediaStore(directory: try makeDirectory(), owner: owner)
        let mock = MockConversations()
        mock.mediaSendError = ErrorSendMessage.transportFailure
        let blob = MockChatMediaBlobStore()
        let controller = makeController(mock, database: try Database.makeTemp().database, store: store, blob: blob)
        let chip = ComposerChip(image: UIImage(data: jpeg())!)
        chip.startUpload(using: ChatMediaUploader(blob: blob))

        #expect(!(await controller.sendMedia([chip], caption: "hi", to: conversationID)))

        let held = try #require(store.entries.first)
        #expect(held.caption == "hi")
        #expect(held.stored == .plain(MockChatMediaBlobStore.blobID))
        #expect(store.imageData(for: held) == blob.storedData.first)

        mock.mediaSendError = nil
        await controller.retry(clientMessageID: held.clientMessageID, in: conversationID)

        #expect(store.entries.isEmpty)
    }
}
