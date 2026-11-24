//
//  ChatArchiveStoreTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Chat archive store")
struct ChatArchiveStoreTests {

    private let owner = try! PublicKey(Data(repeating: 7, count: 32))
    private func id(_ byte: UInt8) -> ConversationID { ConversationID(data: Data(repeating: byte, count: 32)) }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A requested write survives a new store over the same directory")
    func requestSurvivesReload() throws {
        let directory = try makeDirectory()
        let store = ChatArchiveStore(directory: directory, owner: owner)
        store.request(true, for: id(1))
        store.request(false, for: id(2))

        #expect(store.pending == [id(1): true, id(2): false])
        #expect(ChatArchiveStore(directory: directory, owner: owner).pending == [id(1): true, id(2): false])
    }

    @Test("Resolving drops the write only while it still asks for the same thing")
    func resolveMatchesRequest() throws {
        let directory = try makeDirectory()
        let store = ChatArchiveStore(directory: directory, owner: owner)
        store.request(true, for: id(1))

        #expect(!store.resolve(id(1), ifRequested: false))
        #expect(store.pending == [id(1): true])
        #expect(store.resolve(id(1), ifRequested: true))
        #expect(store.pending.isEmpty)
        #expect(ChatArchiveStore(directory: directory, owner: owner).pending.isEmpty)
    }

    @Test("Dropping a chat forgets its write and its cached record")
    func dropForgetsEverything() throws {
        let directory = try makeDirectory()
        let store = ChatArchiveStore(directory: directory, owner: owner)
        store.request(true, for: id(1))
        store.updateCache([id(1): .now])

        store.drop(id(1))

        #expect(store.pending.isEmpty)
        #expect(ChatArchiveReader.load(owner: owner, directory: directory)?.isArchived(id(1)) == false)
    }

    @Test("The extension's reader sees the cache the store wrote, including the viewer's handle")
    func readerSeesStoreWrites() throws {
        let directory = try makeDirectory()
        let store = ChatArchiveStore(directory: directory, owner: owner)
        store.setViewerUsername(Username("ana"))
        store.updateCache([id(2): .now])

        let file = try #require(ChatArchiveReader.load(owner: owner, directory: directory))
        #expect(file.isArchived(id(2)))
        #expect(file.viewerUsername == "ana")
    }

    @Test("Setting the handle keeps the cache")
    func handleKeepsCache() throws {
        let store = ChatArchiveStore(directory: try makeDirectory(), owner: owner)
        store.updateCache([id(3): .now])
        store.setViewerUsername(Username("ana"))
        #expect(store.cachedIDs == [id(3)])
    }

    @Test("A file from before the server held archive state turns its records into archive writes")
    func preServerRecordsBecomeWrites() throws {
        let directory = try makeDirectory()
        var legacy = ChatArchiveFile(viewerUsername: "ana", pending: nil)
        legacy.archive(id(1), at: .now)
        legacy.archive(id(2), at: .now)
        try legacy.write(owner: owner, directory: directory)

        let store = ChatArchiveStore(directory: directory, owner: owner)

        #expect(store.pending == [id(1): true, id(2): true])
        #expect(!store.isUploaded)
        // Written back, so a later launch reads the writes rather than seeding them from the cache.
        let file = try #require(ChatArchiveReader.load(owner: owner, directory: directory))
        #expect(file.pending?.count == 2)
        #expect(file.viewerUsername == "ana")
    }

    @Test("The uploaded marker persists for the account")
    func uploadedMarkerPersists() throws {
        let directory = try makeDirectory()
        ChatArchiveStore(directory: directory, owner: owner).markUploaded()
        #expect(ChatArchiveStore(directory: directory, owner: owner).isUploaded)
    }

    @Test("A corrupt file starts the session with nothing archived")
    func corruptFile() throws {
        let directory = try makeDirectory()
        try Data("not json".utf8).write(to: directory.appendingPathComponent(ChatArchiveFile.filename(owner: owner)))
        let store = ChatArchiveStore(directory: directory, owner: owner)
        #expect(store.pending.isEmpty)
        #expect(store.cachedIDs.isEmpty)
    }
}
