//
//  ChatsBehaviorTests.swift
//  FlipcashCoreVectorsTests
//

import Foundation
import Testing
@testable import FlipcashCore

/// Replays `test-vectors/behaviors/chats/*.json` against ``ChatsModel`` over the seed in that
/// directory's README. Synced copy: a failure is fixed in the canonical files in the orchestrator or
/// in `ChatsModel`, never by editing the copy here.
@Suite("Chats behaviors")
struct ChatsBehaviorTests {

    @Test("Every Chats behavior file replays as written")
    func behaviors() throws {
        let urls = try #require(
            Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/behaviors/chats")
        )
        #expect(!urls.isEmpty, "no behavior files bundled")
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let behavior = try JSONDecoder().decode(Behavior.self, from: Data(contentsOf: url))
            replay(behavior, file: url.lastPathComponent)
        }
    }

    private func replay(_ behavior: Behavior, file: String) {
        var host = ChatsHost()
        for (index, step) in behavior.steps.enumerated() {
            let label = "\(file): step \(index + 1) (\(step.do ?? "ls"))"
            let result = step.do.map { host.perform($0, input: step.input ?? [:]) } ?? .success(())
            switch (result, step.expectError) {
            case (.failure(let code), let expected?):
                #expect(code.rawValue == expected, "\(label): expected error \(expected), got \(code.rawValue)")
                continue
            case (.failure(let code), nil):
                Issue.record("\(label): unexpected error \(code.rawValue)")
                return
            case (.success, let expected?):
                Issue.record("\(label): expected error \(expected), got success")
                continue
            case (.success, nil):
                break
            }
            let state = host.node()
            for (key, want) in step.expect ?? [:] {
                guard let got = state[key] else {
                    Issue.record("\(label): state.\(key): missing on iOS")
                    continue
                }
                #expect(got == want, "\(label): state.\(key): expected \(want), got \(got)")
            }
        }
    }
}

// MARK: - Host

/// The seeded ``ChatsModel`` and the protocol around it: action names, input checks, the state node.
private struct ChatsHost {

    enum ErrorCode: String, Error {
        case unknownAction = "unknown_action"
        case badInput = "bad_input"
    }

    private var model = ChatsModel<String>()

    init() {
        model.update(.project(Self.seed))
    }

    /// The seed table in `behaviors/chats/README.md`, newest first.
    static let seed: [ChatListEntry<String>] = {
        func id(_ prefix: String) -> String { String(repeating: prefix, count: 16) }
        func entry(_ id: String, _ type: ConversationType, unread: Int, archived: Bool = false, age: Int) -> ChatListEntry<String> {
            ChatListEntry(
                id: id,
                type: type,
                lastActivity: Date(timeIntervalSince1970: TimeInterval(1_000_000 - age)),
                isArchived: archived,
                isMuted: false,
                isHidden: false,
                unread: .count(unread)
            )
        }
        return [
            entry(id("01"), .group, unread: 3, age: 1),
            entry(id("02"), .tipDm, unread: 0, age: 2),
            entry(id("03"), .group, unread: 0, age: 3),
            entry(id("04"), .tipDm, unread: 1, age: 4),
            entry("old-crew", .group, unread: 2, archived: true, age: 5),
        ]
    }()

    mutating func perform(_ action: String, input: [String: JSON]) -> Result<Void, ErrorCode> {
        switch action {
        case "FilterSelected":
            guard case .string(let raw)? = input["filter"], let filter = ChatListFilter(rawValue: raw) else {
                return .failure(.badInput)
            }
            model.select(filter)
        case "ChipsRevealed":
            model.revealChips()
        case "SelectionStarted":
            // iOS enters select mode from the More menu with nothing picked; a starting chat isn't
            // part of its API, so `chatId` is checked but not applied.
            if let chatId = input["chatId"] {
                guard case .string = chatId else { return .failure(.badInput) }
            }
            model.beginSelection()
        case "SelectionToggled":
            guard case .string(let id)? = input["chatId"] else { return .failure(.badInput) }
            model.toggle(id)
        case "SelectionEnded":
            model.endSelection()
        default:
            return .failure(.unknownAction)
        }
        return .success(())
    }

    /// The state keys in `behaviors/chats/README.md` that iOS computes in the model. `chats` and
    /// `canReadAll` need `Conversation` and the controller, so they are absent.
    func node() -> [String: JSON] {
        let p = model.projection
        func ids(_ ids: [String]) -> JSON { .array(ids.map(JSON.string)) }
        var state: [String: JSON] = [
            "loading": .bool(model.isLoading),
            "filter": .string(model.filter.rawValue),
            "chipsRevealed": .bool(model.chipsRevealed),
            "showsChips": .bool(model.showsChips),
            "isSelecting": .bool(model.isSelecting),
            "selection": model.isSelecting ? ids(model.selected.sorted()) : .null,
            "showsArchivedRow": .bool(model.showsArchivedRow),
            "hasNoChatsAtAll": .bool(model.hasNoChatsAtAll),
            "visibleChatIds": ids(model.visibleIDs),
        ]
        if let p {
            state["chips"] = .object(Dictionary(uniqueKeysWithValues: ChatListFilter.allCases.map { ($0.rawValue, ids($0.ids(in: p))) }))
            state["unreadChipCount"] = .number(Double(p.unreadChipCount))
            state["groupsChipCount"] = .number(Double(p.groupsChipCount))
            state["archivedRowCount"] = .number(Double(p.archivedRowCount))
            state["tabBadge"] = .number(Double(p.tabBadge))
        }
        return state
    }
}

// MARK: - File format

private struct Behavior: Decodable {
    struct Step: Decodable {
        let `do`: String?
        let input: [String: JSON]?
        let expect: [String: JSON]?
        let expectError: String?
    }
    let screen: String
    let steps: [Step]
}

/// A JSON value, compared exactly: a boolean never equals a number.
private enum JSON: Decodable, Equatable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    var description: String {
        switch self {
        case .null: "null"
        case .bool(let b): "\(b)"
        case .number(let n): n == n.rounded() ? "\(Int(n))" : "\(n)"
        case .string(let s): "\"\(s)\""
        case .array(let a): "[" + a.map(\.description).joined(separator: ", ") + "]"
        case .object(let o): "{" + o.keys.sorted().map { "\($0): \(o[$0]!)" }.joined(separator: ", ") + "}"
        }
    }
}
