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
            owner: .generate()!, selfUserID: me,
            archiveFollowGrace: .zero
        )
        let archive = ChatArchiveStore(directory: directory, owner: owner)
        controller.chatArchive = archive
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
        controller.chatArchive?.writesInFlight.isEmpty ?? true
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

    @Test("Upload: UNIMPLEMENTED costs one call, keeps the records, sends nothing more this session, and a later launch retries")
    func uploadUnimplemented() async throws {
        let directory = try makeDirectory()
        let ids: Set<ConversationID> = [.test(1), .test(2), .test(3)]
        try writeLegacyFile(Array(ids), to: directory)
        let mock = MockConversations()
        mock.feed = [dm(1), dm(2), dm(3)]
        mock.archiveError = ErrorArchiveChat.unimplemented
        let (controller, archive) = makeController(mock, directory: directory)

        await controller.loadFeed()
        try await waitUntil { archive.serverLacksArchive && settled(controller) }

        #expect(mock.archived.count == 1)
        #expect(archive.pending == [.test(1): true, .test(2): true, .test(3): true])
        #expect(!archive.isUploaded)
        #expect(ids.allSatisfy { controller.isArchived($0) })

        await controller.loadFeed()
        #expect(mock.archived.count == 1)

        // A later launch, against a server that now stores archive state.
        mock.archiveError = nil
        let (relaunched, reloaded) = makeController(mock, directory: directory)
        #expect(reloaded.pending == [.test(1): true, .test(2): true, .test(3): true])
        await relaunched.loadFeed()
        try await waitUntil { reloaded.pending.isEmpty && settled(relaunched) }

        #expect(mock.archived.count == 4)
        #expect(Set(mock.archived.dropFirst()) == ids)
        #expect(reloaded.isUploaded)
        #expect(ids.allSatisfy { relaunched.isArchived($0) })
    }

    @Test("A write the server never took doesn't keep a chat the feed no longer lists")
    func unsentWriteDoesNotBlockPrune() async throws {
        let directory = try makeDirectory()
        try writeLegacyFile([.test(3)], to: directory)
        let mock = MockConversations()
        mock.groupFeed = [group(3)]
        mock.archiveError = ErrorArchiveChat.unimplemented
        let (controller, archive) = makeController(mock, directory: directory)
        await controller.loadFeed()
        try await waitUntil { archive.serverLacksArchive && settled(controller) }
        #expect(controller.archivedConversations.map(\.id) == [.test(3)])

        // Removed while the app was closed: neither read lists the group.
        mock.groupFeed = []
        await controller.loadFeed()

        #expect(controller.conversation(withID: .test(3)).map(controller.isMember(of:)) != true)
        #expect(controller.archivedConversations.isEmpty)
        #expect(archive.pending.isEmpty)
    }

    @Test("Upload: a rejection other than DENIED or NOT_FOUND keeps the record for the next sync")
    func uploadOtherRejectionKeeps() async throws {
        let directory = try makeDirectory()
        try writeLegacyFile([.test(1), .test(2)], to: directory)
        let mock = MockConversations()
        mock.feed = [dm(1), dm(2)]
        mock.archiveErrors = [.test(1): ErrorArchiveChat.rejected, .test(2): ErrorArchiveChat.unknown]
        let (controller, archive) = makeController(mock, directory: directory)

        await controller.loadFeed()
        try await waitUntil { mock.archived.count == 2 && settled(controller) }

        #expect(archive.pending == [.test(1): true, .test(2): true])
        #expect(!archive.isUploaded)
        #expect(Set(controller.archivedConversations.map(\.id)) == [.test(1), .test(2)])

        mock.archiveErrors = [:]
        await controller.loadFeed()
        try await waitUntil { archive.pending.isEmpty && settled(controller) }

        #expect(archive.isUploaded)
        #expect(Set(controller.archivedConversations.map(\.id)) == [.test(1), .test(2)])
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

    @Test("A chat moving between folders while the feed is out is kept, though neither read lists it")
    func movingBetweenFoldersKept() async throws {
        let mock = MockConversations()
        mock.feed = [dm(1), dm(2)]
        mock.groupFeed = [group(3)]
        let (controller, archive) = makeController(mock, directory: try makeDirectory())
        await controller.loadFeed()

        // One answered write first, so the next ones go together rather than one at a time.
        controller.archive(.test(2))
        try await waitUntil { archive.pending.isEmpty && settled(controller) }
        mock.archivedFeed = [dm(2, viewerState: archived(1))]

        // Both archives are in flight, and the feed's inbox read already left them out while its
        // archived read predates them: they're in neither list.
        mock.archiveDelay = .milliseconds(300)
        controller.archive(.test(1))
        controller.archive(.test(3))
        #expect(archive.writesInFlight == [.test(1), .test(3)])
        mock.feed = []
        mock.groupFeed = []
        await controller.loadFeed()

        #expect(controller.conversation(withID: .test(1)) != nil)
        #expect(controller.conversation(withID: .test(3)).map(controller.isMember(of:)) == true)
        #expect(Set(controller.archivedConversations.map(\.id)) == [.test(1), .test(2), .test(3)])

        try await waitUntil(timeout: .seconds(3)) { archive.pending.isEmpty && settled(controller) }
        #expect(Set(controller.archivedConversations.map(\.id)) == [.test(1), .test(2), .test(3)])
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

    @Test("A failed archived read skips the prune: a chat the inbox stops listing stays until both folders are read")
    func failedArchivedReadSkipsPrune() async throws {
        let mock = MockConversations()
        mock.feed = [dm(1)]
        mock.groupFeed = [group(3)]
        let (controller, _) = makeController(mock, directory: try makeDirectory())
        await controller.loadFeed()
        #expect(Set(controller.chatListConversations.map(\.id)) == [.test(1), .test(3)])

        // Archived on another device: the inbox stops listing both, and the archived read that
        // would list them fails.
        mock.feed = []
        mock.groupFeed = []
        mock.archivedFeed = [dm(1, viewerState: archived(2))]
        mock.archivedGroupFeed = [group(3, viewerState: archived(2))]
        mock.archivedFeedError = ErrorArchiveChat.transportFailure

        // The reconcile of a held list, then each feed loaded on its own.
        await controller.loadFeed()
        await controller.loadFeed(type: .tipDm)
        await controller.loadGroupFeed()
        #expect(controller.conversation(withID: .test(1)) != nil)
        #expect(controller.conversation(withID: .test(3)).map(controller.isMember(of:)) == true)

        mock.archivedFeedError = nil
        await controller.loadFeed()
        #expect(controller.chatListConversations.isEmpty)
        #expect(Set(controller.archivedConversations.map(\.id)) == [.test(1), .test(3)])
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

    @Test("An archived group open when the follow takes is caught up from its held cursor")
    func openArchivedGroupCatchesUpOnFollow() async throws {
        let mock = MockConversations()
        mock.groupFeed = [group(3)]
        mock.archivedGroupFeed = [group(4, viewerState: archived(1))]
        let (controller, _) = makeController(mock, directory: try makeDirectory())
        controller.start()
        try await waitUntil { mock.streamOpened && mock.connectionStateStreamOpened }
        await controller.loadFeed()
        mock.deltaHead = 5
        await controller.catchUp(conversationID: .test(4))
        let catchUpsBefore = mock.deltaAfterSequences.count

        controller.visibleConversationID = .test(4)
        try await waitUntil { mock.follows == [true] }
        mock.emitConnectionState(.followingArchive)
        try await waitUntil { mock.deltaAfterSequences.count > catchUpsBefore }

        #expect(mock.deltaAfterSequences.last == 5)
    }

    @Test("The follow taking doesn't catch up an open inbox group")
    func openInboxGroupNotCaughtUpOnFollow() async throws {
        let mock = MockConversations()
        mock.groupFeed = [group(3)]
        mock.archivedGroupFeed = [group(4, viewerState: archived(1))]
        let (controller, _) = makeController(mock, directory: try makeDirectory())
        controller.start()
        try await waitUntil { mock.streamOpened && mock.connectionStateStreamOpened }
        await controller.loadFeed()
        mock.deltaHead = 5
        await controller.catchUp(conversationID: .test(3))
        let catchUpsBefore = mock.deltaAfterSequences.count
        let readsBefore = mock.archivedFeedCalls.filter { $0 == .group }.count

        controller.isArchiveScreenVisible = true
        controller.visibleConversationID = .test(3)
        try await waitUntil { mock.follows == [true] }
        mock.emitConnectionState(.followingArchive)
        try await waitUntil { mock.archivedFeedCalls.filter { $0 == .group }.count > readsBefore }

        #expect(mock.deltaAfterSequences.count == catchUpsBefore)
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
