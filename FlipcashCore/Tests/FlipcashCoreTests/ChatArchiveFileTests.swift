//
//  ChatArchiveFileTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Chat archive file")
struct ChatArchiveFileTests {

    private let owner = try! PublicKey(Data(repeating: 7, count: 32))
    private func id(_ byte: UInt8) -> ConversationID { ConversationID(data: Data(repeating: byte, count: 32)) }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A written file round-trips through the reader")
    func roundTrip() throws {
        let directory = try makeDirectory()
        var file = ChatArchiveFile()
        file.archive(id(1), at: Date(timeIntervalSince1970: 10))
        file.viewerUsername = "ana"
        try file.write(owner: owner, directory: directory)

        let read = try #require(ChatArchiveReader.load(owner: owner, directory: directory))
        #expect(read.isArchived(id(1)))
        #expect(!read.isArchived(id(2)))
        #expect(read.viewerUsername == "ana")
    }

    @Test("A missing file reads as nil, not as an empty archive")
    func missingFile() throws {
        #expect(ChatArchiveReader.load(owner: owner, directory: try makeDirectory()) == nil)
    }

    @Test("A file from another schema version reads as nil")
    func versionMismatch() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent(ChatArchiveFile.filename(owner: owner))
        try Data(#"{"version":99,"archived":{}}"#.utf8).write(to: url)
        #expect(ChatArchiveReader.load(owner: owner, directory: directory) == nil)
    }

    @Test("Another owner's file is not read")
    func ownerScoped() throws {
        let directory = try makeDirectory()
        var file = ChatArchiveFile()
        file.archive(id(1), at: .now)
        try file.write(owner: owner, directory: directory)

        let other = try PublicKey(Data(repeating: 8, count: 32))
        #expect(ChatArchiveReader.load(owner: other, directory: directory) == nil)
    }

    @Test("A file written before the server held archive state reads, and its records are archives to upload")
    func preServerFile() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent(ChatArchiveFile.filename(owner: owner))
        let key = ChatArchiveFile.key(id(1))
        try Data(#"{"version":1,"viewerUsername":"ana","archived":{"\#(key)":0}}"#.utf8).write(to: url)

        let file = try #require(ChatArchiveReader.load(owner: owner, directory: directory))
        #expect(file.isArchived(id(1)))
        #expect(file.viewerUsername == "ana")
        #expect(file.pending == nil)
        #expect(file.pendingWrites == [id(1): true])
    }

    @Test("Once uploaded, a file without pending writes has nothing to upload")
    func uploadedFileHasNothingToUpload() {
        var file = ChatArchiveFile(pending: nil, uploaded: true)
        file.archive(id(1), at: .now)
        #expect(file.pendingWrites.isEmpty)
    }

    @Test("Recording the cache keeps the date a chat that stays archived already had")
    func setArchivedKeepsDates() {
        var file = ChatArchiveFile()
        let first = Date(timeIntervalSince1970: 100)
        file.setArchived([id(1): first])
        file.setArchived([id(1): Date(timeIntervalSince1970: 200), id(2): first])
        #expect(file.archived[ChatArchiveFile.key(id(1))] == first)
        #expect(file.archivedIDs == [id(1), id(2)])
    }
}
