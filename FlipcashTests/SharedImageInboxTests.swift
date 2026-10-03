//
//  SharedImageInboxTests.swift
//  FlipcashTests
//

import Foundation
import Testing

@testable import FlipcashCore

@Suite("Shared Image Inbox")
struct SharedImageInboxTests {

    /// A directory standing in for the App Group container, removed when the test ends.
    private func makeContainer() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("a written image reads back and is then gone")
    func writeThenTake() throws {
        let directory = try makeContainer()
        defer { try? FileManager.default.removeItem(at: directory) }

        let inbox = SharedImageInbox(container: directory)
        let payload = Data("not really a jpeg".utf8)

        try inbox.deposit(payload)

        #expect(try inbox.take() == payload)
        // Taken, not read: the app consumes the handover once, so a relaunch does not rescan
        // an image the user already dealt with.
        #expect(try inbox.take() == nil)
    }

    @Test("an empty inbox yields nothing")
    func emptyInbox() throws {
        let directory = try makeContainer()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try SharedImageInbox(container: directory).take() == nil)
    }

    @Test("a second deposit replaces the first")
    func depositReplaces() throws {
        let directory = try makeContainer()
        defer { try? FileManager.default.removeItem(at: directory) }

        let inbox = SharedImageInbox(container: directory)

        try inbox.deposit(Data("first".utf8))
        try inbox.deposit(Data("second".utf8))

        #expect(try inbox.take() == Data("second".utf8))
    }

    @Test("the handoff URL carries a nonce so two shares are two deep links")
    func handoffURLIsUnique() {
        // `DeepLinkController` drops a repeat of the same URL within its repeat window, so a
        // constant URL would make sharing a second image a no-op.
        #expect(SharedImageInbox.handoffURL() != SharedImageInbox.handoffURL())
    }

    @Test("the handoff URL is recognised as the handoff")
    func handoffURLIsIdentified() {
        #expect(SharedImageInbox.isHandoff(SharedImageInbox.handoffURL()))
        #expect(!SharedImageInbox.isHandoff(URL(string: "flipcash://balance")!))
    }
}
