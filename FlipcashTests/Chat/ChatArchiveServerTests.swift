//
//  ChatArchiveServerTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// Archive held by the server: the writes, the one-time upload, the feed folders, FollowArchive,
/// and the catch-up after an unarchive.
@MainActor
@Suite("Chat archive against the server")
struct ChatArchiveServerTests {

    private let owner = try! PublicKey(Data(repeating: 7, count: 32))
    private let me = UUID()

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeController(_ mock: MockConversations, directory: URL) -> (ConversationController, ChatArchiveStore) {
        let controller = ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: try! Database.makeTemp().database,
            owner: .generate()!, selfUserID: me
        )
        let archive = ChatArchiveStore(directory: directory, owner: owner)
        controller.chatArchive = archive
        controller.archiveFollowGrace = .zero
        return (controller, archive)
    }

    /// Writes a file as the release before server archive left it: records, no pending writes.
    private func writeLegacyFile(_ ids: [ConversationID], to directory: URL) throws {
        var file = ChatArchiveFile(pending: nil)
        for id in ids { file.archive(id, at: .now) }
        try file.write(owner: owner, directory: directory)
    }

    private func dm(_ byte: UInt8, viewerState: ConversationViewerState? = nil) -> Conversation {
        Conversation(
            id: .test(byte), members: [ConversationMember(userID: me, displayName: "")],
            lastMessage: nil, lastActivity: Date(timeIntervalSince1970: TimeInterval(byte)), type: .tipDm,
            viewerState: viewerState
        )
    }

    private func group(_ byte: UInt8, viewerState: ConversationViewerState? = nil) -> Conversation {
        Conversation(
            id: .test(byte), members: [ConversationMember(userID: me, displayName: "")],
            lastMessage: nil, lastActivity: Date(timeIntervalSince1970: TimeInterval(byte)), type: .group,
            latestEventSequence: 7, viewerState: viewerState
        )
    }

    private func archived(_ version: UInt64) -> ConversationViewerState {
        ConversationViewerState(mute: nil, version: version, archive: ConversationArchiveState(archivedAt: .now))
    }

    private func unarchived(_ version: UInt64) -> ConversationViewerState {
        ConversationViewerState(mute: nil, version: version, archive: nil)
    }

    private func settled(_ controller: ConversationController) -> Bool {
        controller.archiveWritesInFlight.isEmpty
    }

    // MARK: - One-time upload (D3)

    @Test("Upload: OK applies the viewer state; DENIED and NOT_FOUND drop the record; then the marker is set")
    func uploadOutcomes() async throws {
        let directory = try makeDirectory()
        try writeLegacyFile([.test(1), .test(3), .test(4)], to: directory)
        let mock = MockConversations()
        mock.feed = [dm(1), dm(3), dm(4)]
        mock.archiveErrors = [.test(3): ErrorArchiveChat.denied, .test(4): ErrorArchiveChat.notFound]
        let (controller, archive) = makeController(mock, directory: directory)

        await controller.loadFeed()
        try await waitUntil { mock.archived.count == 3 && settled(controller) }

        #expect(Set(mock.archived) == [.test(1), .test(3), .test(4)])
        #expect(archive.pending.isEmpty)
        #expect(archive.isUploaded)
        #expect(controller.conversation(withID: .test(1))?.viewerState?.isArchived == true)
        #expect(controller.archivedConversations.map(\.id) == [.test(1)])
        #expect(Set(controller.chatListConversations.map(\.id)) == [.test(3), .test(4)])
        #expect(ChatArchiveReader.load(owner: owner, directory: directory)?.archivedIDs == [.test(1)])
    }

    @Test("Upload: UNIMPLEMENTED keeps the records, sends nothing more this session, and a later launch retries")
    func uploadUnimplemented() async throws {
        let directory = try makeDirectory()
        try writeLegacyFile([.test(1)], to: directory)
        let mock = MockConversations()
        mock.feed = [dm(1)]
        mock.archiveError = ErrorArchiveChat.unimplemented
        let (controller, archive) = makeController(mock, directory: directory)

        await controller.loadFeed()
        try await waitUntil { controller.serverLacksArchive && settled(controller) }

        #expect(archive.pending == [.test(1): true])
        #expect(!archive.isUploaded)
        #expect(controller.isArchived(.test(1)))

        await controller.loadFeed()
        #expect(mock.archived == [.test(1)])

        // A later launch, against a server that now stores archive state.
        mock.archiveError = nil
        let (relaunched, reloaded) = makeController(mock, directory: directory)
        #expect(reloaded.pending == [.test(1): true])
        await relaunched.loadFeed()
        try await waitUntil { reloaded.pending.isEmpty && settled(relaunched) }

        #expect(mock.archived == [.test(1), .test(1)])
        #expect(reloaded.isUploaded)
        #expect(relaunched.isArchived(.test(1)))
    }

    @Test("Upload: a record the server already shows as archived needs no call")
    func uploadAlreadyArchived() async throws {
        let directory = try makeDirectory()
        try writeLegacyFile([.test(1)], to: directory)
        let mock = MockConversations()
        mock.feed = [dm(1, viewerState: archived(3))]
        let (controller, archive) = makeController(mock, directory: directory)

        await controller.loadFeed()

        #expect(mock.archived.isEmpty)
        #expect(archive.pending.isEmpty)
        #expect(archive.isUploaded)
    }

    // MARK: - Writes (D2)

    @Test("A write that fails in transit stays and the next feed sync retries it")
    func transientFailureRetries() async throws {
        let mock = MockConversations()
        mock.feed = [dm(1)]
        let (controller, archive) = makeController(mock, directory: try makeDirectory())
        await controller.loadFeed()

        mock.archiveError = ErrorArchiveChat.transportFailure
        controller.archive(.test(1))
        try await waitUntil { mock.archived.count == 1 && settled(controller) }

        #expect(archive.pending == [.test(1): true])
        #expect(controller.isArchived(.test(1)))
        #expect(controller.archivedConversations.map(\.id) == [.test(1)])

        mock.archiveError = nil
        await controller.loadFeed()
        try await waitUntil { archive.pending.isEmpty && settled(controller) }

        #expect(mock.archived.count == 2)
        #expect(controller.conversation(withID: .test(1))?.viewerState?.isArchived == true)
    }

    @Test("Unarchiving while the archive is in flight sends the unarchive once it lands")
    func toggleDuringFlight() async throws {
        let mock = MockConversations()
        mock.feed = [dm(1)]
        mock.archiveDelay = .milliseconds(50)
        let (controller, archive) = makeController(mock, directory: try makeDirectory())
        await controller.loadFeed()

        controller.archive(.test(1))
        controller.unarchive(.test(1))
        #expect(!controller.isArchived(.test(1)))
        try await waitUntil { archive.pending.isEmpty && settled(controller) && !mock.unarchived.isEmpty }

        #expect(mock.archived == [.test(1)])
        #expect(mock.unarchived == [.test(1)])
        #expect(!controller.isArchived(.test(1)))
    }

    // MARK: - Version order (D1)

    @Test("Archive applies by viewer-state version: an older stream event or feed row doesn't undo it")
    func versionOrderedApply() async throws {
        let directory = try makeDirectory()
        let mock = MockConversations()
        mock.feed = [dm(1), dm(2)]
        let (controller, archive) = makeController(mock, directory: directory)
        controller.start()
        try await waitUntil { mock.streamOpened }
        await controller.loadFeed()

        mock.archiveVersion = 4
        controller.archive(.test(1))
        try await waitUntil { archive.pending.isEmpty && settled(controller) }
        #expect(controller.conversation(withID: .test(1))?.viewerState?.version == 5)

        // An older event, then a marker event on another chat to know the first was handled.
        mock.emit(.viewerStateChanged(conversationID: .test(1), viewerState: unarchived(3)))
        mock.emit(.viewerStateChanged(conversationID: .test(2), viewerState: archived(1)))
        try await waitUntil { controller.isArchived(.test(2)) }
        #expect(controller.isArchived(.test(1)))

        mock.feed = [dm(1, viewerState: unarchived(2)), dm(2, viewerState: archived(1))]
        await controller.loadFeed()
        #expect(controller.isArchived(.test(1)))

        mock.emit(.viewerStateChanged(conversationID: .test(1), viewerState: unarchived(6)))
        try await waitUntil { !controller.isArchived(.test(1)) }
        #expect(ChatArchiveReader.load(owner: owner, directory: directory)?.archivedIDs == [.test(2)])
    }

    // MARK: - Feeds (D4)

    @Test("A feed sync keeps archived DMs and groups the inbox no longer lists, on both load paths")
    func feedPruneKeepsArchived() async throws {
        let mock = MockConversations()
        mock.feed = [dm(1)]
        mock.archivedFeed = [dm(2, viewerState: archived(1))]
        mock.groupFeed = [group(3)]
        mock.archivedGroupFeed = [group(4, viewerState: archived(1))]
        let (controller, _) = makeController(mock, directory: try makeDirectory())

        // The empty-store load, then the reconcile of a store that already holds the chats.
        for _ in 0..<2 {
            await controller.loadFeed()
            #expect(Set(controller.chatListConversations.map(\.id)) == [.test(1), .test(3)])
            #expect(Set(controller.archivedConversations.map(\.id)) == [.test(2), .test(4)])
        }
        #expect(mock.archivedFeedCalls.contains(.group))
        #expect(mock.archivedFeedCalls.contains(.dm(.tipDm)))
    }

    @Test("A group archived on another device while offline moves to Archived on the next sync, not out of the store")
    func archivedElsewhereWhileOffline() async throws {
        let mock = MockConversations()
        mock.groupFeed = [group(3)]
        let (controller, _) = makeController(mock, directory: try makeDirectory())
        await controller.loadFeed()
        #expect(controller.chatListConversations.map(\.id) == [.test(3)])

        mock.groupFeed = []
        mock.archivedGroupFeed = [group(3, viewerState: archived(2))]
        await controller.loadFeed()

        #expect(controller.chatListConversations.isEmpty)
        #expect(controller.archivedConversations.map(\.id) == [.test(3)])
    }

    @Test("When the archived read fails, the sync keeps the archived chats it holds")
    func failedArchivedReadKeepsHeld() async throws {
        let mock = MockConversations()
        mock.archivedFeed = [dm(2, viewerState: archived(1))]
        mock.archivedGroupFeed = [group(4, viewerState: archived(1))]
        let (controller, _) = makeController(mock, directory: try makeDirectory())
        await controller.loadFeed()
        #expect(Set(controller.archivedConversations.map(\.id)) == [.test(2), .test(4)])

        mock.archivedFeedError = ErrorArchiveChat.transportFailure
        await controller.loadFeed()

        #expect(Set(controller.archivedConversations.map(\.id)) == [.test(2), .test(4)])
    }

    // MARK: - FollowArchive (D5)

    @Test("The Archived screen turns following on; the ack re-reads archived groups without dropping the inbox")
    func archiveScreenFollows() async throws {
        let mock = MockConversations()
        mock.groupFeed = [group(3)]
        mock.archivedGroupFeed = [group(4, viewerState: archived(1))]
        let (controller, _) = makeController(mock, directory: try makeDirectory())
        controller.start()
        try await waitUntil { mock.streamOpened && mock.connectionStateStreamOpened }
        await controller.loadFeed()
        let readsBefore = mock.archivedFeedCalls.filter { $0 == .group }.count

        controller.isArchiveScreenVisible = true
        try await waitUntil { mock.follows == [true] }

        mock.archivedGroupFeed = [group(4, viewerState: archived(1)), group(5, viewerState: archived(1))]
        mock.emitConnectionState(.followingArchive)
        try await waitUntil { controller.archivedConversations.count == 2 }

        #expect(mock.archivedFeedCalls.filter { $0 == .group }.count == readsBefore + 1)
        #expect(controller.chatListConversations.map(\.id) == [.test(3)])
        #expect(Set(controller.archivedConversations.map(\.id)) == [.test(4), .test(5)])

        controller.isArchiveScreenVisible = false
        try await waitUntil { mock.follows == [true, false] }
    }

    @Test("Opening an archived group from the Archived screen keeps following on until the user leaves both")
    func pushIntoArchivedGroupKeepsFollowing() async throws {
        let mock = MockConversations()
        mock.archivedGroupFeed = [group(4, viewerState: archived(1))]
        mock.groupFeed = [group(3)]
        let (controller, _) = makeController(mock, directory: try makeDirectory())
        await controller.loadFeed()

        controller.isArchiveScreenVisible = true
        // The push: the screen disappears before or after the chat appears.
        controller.isArchiveScreenVisible = false
        controller.visibleConversationID = .test(4)
        try await waitUntil { mock.follows == [true] }

        // An inbox group doesn't keep it on.
        controller.visibleConversationID = .test(3)
        try await waitUntil { mock.follows == [true, false] }

        // An archived group on its own turns it on.
        controller.visibleConversationID = .test(4)
        try await waitUntil { mock.follows == [true, false, true] }
        controller.visibleConversationID = nil
        try await waitUntil { mock.follows == [true, false, true, false] }
    }

    // MARK: - Unarchive catch-up (D6)

    @Test("Unarchiving a group applies the returned chat and catches its transcript up")
    func unarchiveGroupCatchesUp() async throws {
        let mock = MockConversations()
        mock.archivedGroupFeed = [group(4, viewerState: archived(1))]
        // The reply's viewer state is the next version after the archive the feed carried.
        mock.archiveVersion = 1
        mock.unarchiveChatResult = .some(Conversation(
            id: .test(4), members: [ConversationMember(userID: me, displayName: "")],
            lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 4), type: .group,
            title: "Back", latestEventSequence: 9, viewerState: unarchived(2)
        ))
        let (controller, archive) = makeController(mock, directory: try makeDirectory())
        await controller.loadFeed()
        let catchUpsBefore = mock.deltaAfterSequences.count

        controller.unarchive(.test(4))
        try await waitUntil { archive.pending.isEmpty && settled(controller) && mock.deltaAfterSequences.count > catchUpsBefore }

        #expect(mock.unarchived == [.test(4)])
        #expect(controller.chatListConversations.map(\.id) == [.test(4)])
        #expect(controller.conversation(withID: .test(4))?.title == "Back")
    }

    @Test("Another device's unarchive of a group catches its transcript up")
    func unarchiveElsewhereCatchesUp() async throws {
        let mock = MockConversations()
        mock.archivedGroupFeed = [group(4, viewerState: archived(1))]
        let (controller, _) = makeController(mock, directory: try makeDirectory())
        controller.start()
        try await waitUntil { mock.streamOpened }
        await controller.loadFeed()
        let catchUpsBefore = mock.deltaAfterSequences.count

        mock.emit(.viewerStateChanged(conversationID: .test(4), viewerState: unarchived(2)))
        try await waitUntil { mock.deltaAfterSequences.count > catchUpsBefore }

        #expect(controller.chatListConversations.map(\.id) == [.test(4)])
        #expect(mock.unarchived.isEmpty)
    }

    // MARK: - Removal (D7)

    @Test("Being removed from an archived group drops its archive and sends nothing")
    func ownRemovalDropsArchive() async throws {
        let directory = try makeDirectory()
        let mock = MockConversations()
        mock.archivedGroupFeed = [group(4, viewerState: archived(1))]
        let (controller, archive) = makeController(mock, directory: directory)
        controller.start()
        try await waitUntil { mock.streamOpened }
        await controller.loadFeed()
        #expect(ChatArchiveReader.load(owner: owner, directory: directory)?.isArchived(.test(4)) == true)

        mock.emit(.rosterChanged(conversationID: .test(4), updates: [
            DecodedRosterUpdate(rosterSummary: ConversationRosterSummary(memberCount: 0, version: 2), change: .left(userID: me)),
        ]))
        try await waitUntil { ChatArchiveReader.load(owner: owner, directory: directory)?.isArchived(.test(4)) == false }

        #expect(archive.pending.isEmpty)
        #expect(!controller.isArchived(.test(4)))
        #expect(mock.unarchived.isEmpty)
    }
}
