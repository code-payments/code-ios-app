//
//  ChatArchiveVectorTests.swift
//  FlipcashCoreVectorsTests
//

import Foundation
import Testing
@testable import FlipcashCore

/// `test-vectors/chat_archive.json`. Synced copy: a failure is fixed in the canonical fixture or in
/// `ChatArchiveRules` / `ChatListProjection`, never by editing the copy here.
struct ChatArchiveFixture: Decodable {

    /// `true`, `false` or the string `"unknown"`.
    struct Signal: Decodable {
        let value: ChatArchiveSignal
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self) { value = b ? .yes : .no }
            else if try c.decode(String.self) == "unknown" { value = .unknown }
            else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "expected bool or \"unknown\"") }
        }
    }

    /// An integer or the string `"unknown"`.
    struct Unread: Decodable {
        let value: ChatListUnread
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(Int.self) { value = .count(n) }
            else if try c.decode(String.self) == "unknown" { value = .unknown }
            else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "expected int or \"unknown\"") }
        }
    }

    struct NotifyVector: Decodable {
        struct Push: Decodable {
            let archived: Bool
            let muted: Bool
            let kind: String
            let mentionsViewer: Signal
            let repliesToViewer: Signal
        }
        struct Expect: Decodable { let notify: Bool; let archived: Bool }
        let name: String
        let push: Push
        let expect: Expect
        let note: String
    }

    struct ListVector: Decodable {
        struct Chat: Decodable {
            let id: String
            let type: String
            let lastActivity: Int
            let archived: Bool
            let muted: Bool
            let hidden: Bool
            let unread: Unread
        }
        struct Expect: Decodable {
            struct Counts: Decodable { let unread: Int; let groups: Int }
            struct Row: Decodable { let visible: Bool; let count: Int }
            let main: [String]
            let unreadChip: [String]
            let groupsChip: [String]
            let archived: [String]
            let chipCounts: Counts
            let archivedRow: Row
            let tabBadge: Int
        }
        let name: String
        let chats: [Chat]
        let expect: Expect
        let note: String
    }

    let notify: [NotifyVector]
    let list: [ListVector]

    static func load() throws -> ChatArchiveFixture {
        let url = try #require(
            Bundle.module.url(forResource: "chat_archive", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(ChatArchiveFixture.self, from: Data(contentsOf: url))
    }
}

@Suite("Chat archive vectors")
struct ChatArchiveVectorTests {

    @Test("Every notify vector decides as the fixture says")
    func notifyVectors() throws {
        for vector in try ChatArchiveFixture.load().notify {
            let outcome = ChatArchiveRules.decide(
                .init(
                    archived: vector.push.archived,
                    muted: vector.push.muted,
                    mentionsViewer: vector.push.mentionsViewer.value,
                    repliesToViewer: vector.push.repliesToViewer.value
                )
            )
            #expect(outcome.notify == vector.expect.notify, "\(vector.name): notify. \(vector.note)")
            #expect(outcome.archived == vector.expect.archived, "\(vector.name): archived. \(vector.note)")
        }
    }

    @Test("Every list vector projects as the fixture says")
    func listVectors() throws {
        for vector in try ChatArchiveFixture.load().list {
            let entries = vector.chats.map {
                ChatListEntry(
                    id: $0.id,
                    type: $0.type == "group" ? .group : .tipDm,
                    lastActivity: Date(timeIntervalSince1970: TimeInterval($0.lastActivity)),
                    isArchived: $0.archived,
                    isMuted: $0.muted,
                    isHidden: $0.hidden,
                    unread: $0.unread.value
                )
            }
            let p = ChatListProjection.project(entries)
            let e = vector.expect
            #expect(p.main == e.main, "\(vector.name): main. \(vector.note)")
            #expect(p.unreadChip == e.unreadChip, "\(vector.name): unreadChip")
            #expect(p.groupsChip == e.groupsChip, "\(vector.name): groupsChip")
            #expect(p.archived == e.archived, "\(vector.name): archived")
            #expect(p.unreadChipCount == e.chipCounts.unread, "\(vector.name): unread count")
            #expect(p.groupsChipCount == e.chipCounts.groups, "\(vector.name): groups count")
            #expect(p.archivedRowVisible == e.archivedRow.visible, "\(vector.name): row visible")
            #expect(p.archivedRowCount == e.archivedRow.count, "\(vector.name): row count")
            #expect(p.tabBadge == e.tabBadge, "\(vector.name): tab badge")
        }
    }
}
