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
}
