//
//  ShareInputTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FlipcashCore

@Suite("Share input")
@MainActor
struct ShareInputTests {

    private static func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("share-input-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func pngFile(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    private static func text(_ string: String) -> NSItemProvider {
        NSItemProvider(item: string as NSString, typeIdentifier: UTType.plainText.identifier)
    }

    private static func link(_ string: String) -> NSItemProvider {
        NSItemProvider(item: URL(string: string)! as NSURL, typeIdentifier: UTType.url.identifier)
    }

    @Test("Shared text prefills the message")
    func sharedText() async throws {
        let input = await ShareInput.parse([Self.text("  hello there \n")])
        #expect(input.text == "hello there")
        #expect(input.imageURLs.isEmpty)
    }

    @Test("A web link prefills the message")
    func sharedLink() async {
        let input = await ShareInput.parse([Self.link("https://example.com/a?b=1")])
        #expect(input.text == "https://example.com/a?b=1")
    }

    @Test("A link wins over the page title Safari sends beside it")
    func linkWinsOverTitle() async {
        let input = await ShareInput.parse([Self.text("Example page"), Self.link("https://example.com")])
        #expect(input.text == "https://example.com")
    }

    @Test("A file URL is not message text")
    func fileURLIsNotALink() async {
        let input = await ShareInput.parse([NSItemProvider(item: URL(fileURLWithPath: "/tmp/x.pdf") as NSURL, typeIdentifier: UTType.url.identifier)])
        #expect(input.text == nil)
        #expect(input.isEmpty)
    }

    @Test("Blank text prefills nothing")
    func blankText() async {
        let input = await ShareInput.parse([Self.text("  \n ")])
        #expect(input.text == nil)
    }

    @Test("Images are copied out of the provider and keep share order")
    func images() async throws {
        let source = try Self.scratchDirectory()
        let destination = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: destination) }
        let first = try Self.pngFile(in: source)
        let second = try Self.pngFile(in: source)
        let providers = [first, second].map { NSItemProvider(contentsOf: $0)! }

        let input = await ShareInput.parse(providers, temporaryDirectory: destination)

        #expect(input.imageURLs.count == 2)
        for url in input.imageURLs {
            #expect(url.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        input.removeFiles()
        #expect(input.imageURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("Images past the limit are counted, not kept")
    func imageLimit() async throws {
        let source = try Self.scratchDirectory()
        let destination = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: destination) }
        let providers = try (0..<3).map { _ in NSItemProvider(contentsOf: try Self.pngFile(in: source))! }

        let input = await ShareInput.parse(providers, maxImages: 2, temporaryDirectory: destination)

        #expect(input.imageURLs.count == 2)
        #expect(input.droppedImageCount == 1)
    }
}

@Suite("Share chat selection")
struct ShareChatSelectionTests {

    private static func conversation(_ byte: UInt8, size: Int = 32, activity: TimeInterval, type: ConversationType = .tipDm, hidden: Bool = false) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: byte, count: size)),
            members: [],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSinceReferenceDate: activity),
            type: type,
            isHidden: hidden
        )
    }

    @Test("Candidates are the Chats tab's main list: newest first, no hidden, archived, contact or unjoined chats")
    func candidates() {
        let old = Self.conversation(1, activity: 10)
        let new = Self.conversation(2, activity: 30)
        let hidden = Self.conversation(3, activity: 40, hidden: true)
        let middle = Self.conversation(4, activity: 20, type: .group)
        let archived = Self.conversation(5, activity: 50)
        let contact = Self.conversation(6, activity: 60, type: .contactDm)
        let unjoined = Self.conversation(7, activity: 70, type: .group)

        let result = ShareChatSelection.candidates(
            from: [old, hidden, new, middle, archived, contact, unjoined],
            joinedGroupIDs: [middle.id],
            archivedIDs: [archived.id]
        )

        #expect(result.map(\.id) == [new.id, middle.id, old.id])
    }

    @Test("A DM is preselected by its base64url identifier")
    func preselectsDM() {
        let dm = Self.conversation(1, activity: 1)
        let other = Self.conversation(2, activity: 2)
        #expect(ShareChatSelection.preselected(conversationIdentifier: dm.id.linkPathComponent, in: [dm, other]) == dm.id)
    }

    @Test("A group is preselected by its UUID identifier")
    func preselectsGroup() {
        let group = Self.conversation(7, size: 16, activity: 1)
        #expect(ShareChatSelection.preselected(conversationIdentifier: group.id.linkPathComponent, in: [group]) == group.id)
    }

    @Test("A missing, malformed or unknown identifier selects nothing")
    func preselectsNothing() {
        let dm = Self.conversation(1, activity: 1)
        let unknown = Self.conversation(9, activity: 1)
        #expect(ShareChatSelection.preselected(conversationIdentifier: nil, in: [dm]) == nil)
        #expect(ShareChatSelection.preselected(conversationIdentifier: "not an id", in: [dm]) == nil)
        #expect(ShareChatSelection.preselected(conversationIdentifier: unknown.id.linkPathComponent, in: [dm]) == nil)
    }
}

@Suite("Share send plan")
struct ShareSendPlanTests {

    @Test("Text alone is one text message")
    func textOnly() {
        #expect(ShareSendPlan.steps(imageCount: 0, text: " hi ") == [.text("hi")])
    }

    @Test("Nothing to send plans nothing")
    func empty() {
        #expect(ShareSendPlan.steps(imageCount: 0, text: "  ").isEmpty)
        #expect(ShareSendPlan.steps(imageCount: 0, text: nil).isEmpty)
    }

    @Test("The caption goes under the last photo only")
    func captionOnLast() {
        #expect(ShareSendPlan.steps(imageCount: 3, text: "look") == [
            .photo(index: 0, caption: nil),
            .photo(index: 1, caption: nil),
            .photo(index: 2, caption: "look"),
        ])
    }

    @Test("Photos with no text carry no caption")
    func noCaption() {
        #expect(ShareSendPlan.steps(imageCount: 1, text: nil) == [.photo(index: 0, caption: nil)])
    }
}
