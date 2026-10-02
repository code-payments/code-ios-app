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

    @Test("Archiving a chat is visible at once and survives a new store over the same directory")
    func archiveSurvivesReload() throws {
        let directory = try makeDirectory()
        let store = ChatArchiveStore(directory: directory, owner: owner)
        store.archive(id(1))

        #expect(store.isArchived(id(1)))
        #expect(ChatArchiveStore(directory: directory, owner: owner).isArchived(id(1)))
    }

    @Test("Unarchiving removes the record on disk")
    func unarchive() throws {
        let directory = try makeDirectory()
        let store = ChatArchiveStore(directory: directory, owner: owner)
        store.archive(id(1))
        store.unarchive(id(1))

        #expect(!store.isArchived(id(1)))
        #expect(ChatArchiveReader.load(owner: owner, directory: directory)?.isArchived(id(1)) == false)
    }

    @Test("The extension's reader sees what the store wrote, including the viewer's handle")
    func readerSeesStoreWrites() throws {
        let directory = try makeDirectory()
        let store = ChatArchiveStore(directory: directory, owner: owner)
        store.setViewerUsername(Username("ana"))
        store.archive(id(2))

        let file = try #require(ChatArchiveReader.load(owner: owner, directory: directory))
        #expect(file.isArchived(id(2)))
        #expect(file.viewerUsername == "ana")
    }

    @Test("Setting the handle does not drop archived chats")
    func handleKeepsArchive() throws {
        let store = ChatArchiveStore(directory: try makeDirectory(), owner: owner)
        store.archive(id(3))
        store.setViewerUsername(Username("ana"))
        #expect(store.isArchived(id(3)))
    }

    @Test("A corrupt file starts the session with nothing archived")
    func corruptFile() throws {
        let directory = try makeDirectory()
        try Data("not json".utf8).write(to: directory.appendingPathComponent(ChatArchiveFile.filename(owner: owner)))
        #expect(ChatArchiveStore(directory: directory, owner: owner).archivedIDs.isEmpty)
    }
}
