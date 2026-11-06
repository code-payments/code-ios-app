import Foundation
import Testing
@testable import FlipcashCore

/// `chat_media_groups.json`: which photos the transcript draws as one card stack. The canonical
/// copy lives in the orchestrator repo; this one is synced byte for byte and never edited here.
@Suite struct ChatMediaGroupingVectorTests {

    struct Message: Decodable, Sendable {
        let seq: UInt64
        let sender: String
        let kind: String
        let ts: Double
        let hasCaption: Bool
        let isReply: Bool
    }

    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let note: String
        let messages: [Message]
        let stacks: [[UInt64]]

        var testDescription: String { name }
    }

    struct Fixture: Decodable {
        let windowSeconds: Double
        let cases: [Vector]
    }

    static let fixture: Fixture? = try? loadFixture()
    static let vectors: [Vector] = fixture?.cases ?? []

    private static func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "chat_media_groups", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureLoadsAllCases() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.cases.count == 12)
        #expect(fixture.windowSeconds == ChatMediaGrouping.window)
    }

    @Test(arguments: vectors)
    func stacksMatchTheCrossPlatformVector(_ vector: Vector) {
        var senders: [String: UserID] = [:]
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let members = vector.messages.map { message in
            let sender = senders[message.sender] ?? UUID()
            senders[message.sender] = sender
            return ChatMediaGrouping.Member(
                seq: message.seq,
                sender: sender,
                isPhoto: message.kind == "photo",
                date: epoch.addingTimeInterval(message.ts),
                hasCaption: message.hasCaption,
                isReply: message.isReply
            )
        }
        let stacks = ChatMediaGrouping.stacks(members).map { range in members[range].map(\.seq) }
        #expect(stacks == vector.stacks, "\(vector.note)")
    }
}
