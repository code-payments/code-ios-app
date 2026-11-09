//
//  ChatsPuppetHost.swift
//  ChatsPuppet
//

import Foundation
import FlipcashCore

/// The Chats screen's Puppet host: the seeded ``ChatsModel`` behind the request and response shapes
/// in the orchestrator's `docs/puppet/PROTOCOL.md`. `ChatsBehaviorTests` replays the shared behavior
/// files through it in-process, and `chats-puppet-host` answers the same requests as lines on stdin
/// for the orchestrator's `puppet` CLI.
///
/// ``ChatsModel`` is synchronous and reads no services, so there is nothing to settle before a
/// reply and nothing for a fixture guard to catch.
public struct ChatsPuppetHost {

    public enum ErrorCode: String, Error {
        case badRequest = "bad_request"
        case unknownAction = "unknown_action"
        case badInput = "bad_input"
    }

    public static let screen = "Chats"

    /// The only route `launch` accepts: the Chats tab, in the form both apps' deep links use.
    public static let route = "/tab/chats"

    private var model = ChatsModel<String>()

    /// Screens pushed over the list. They aren't hosted: each shows its name and lends `Back`.
    private var stack: [ChatsDestination<String>] = []

    /// The screen names from the list to the top screen.
    public var path: [String] { [Self.screen] + stack.map(Self.name) }

    public init() {
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

    // MARK: - Actions

    private static func schema(_ properties: [String: JSON], required: [String] = []) -> JSON {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSON.string)),
        ])
    }

    /// `Back`, which the host lends to every screen above the list.
    public static let back: (name: String, input: JSON) = ("Back", schema([:]))

    /// The list's actions and their input schemas, in the form the Android host lists them.
    public static let actions: [(name: String, input: JSON)] = {
        let chatId: JSON = .object(["type": .string("string"), "format": .string("ChatId")])
        return [
            ("FilterSelected", schema(
                ["filter": .object(["type": .string("string"), "enum": .array(ChatListFilter.allCases.map { .string($0.rawValue) })])],
                required: ["filter"]
            )),
            ("ChipsRevealed", schema([:])),
            ("SelectionStarted", schema(["chatId": chatId])),
            ("SelectionToggled", schema(["chatId": chatId], required: ["chatId"])),
            ("SelectionEnded", schema([:])),
            ("ChatOpened", schema(["chatId": chatId], required: ["chatId"])),
            ("ArchivedOpened", schema([:])),
            ("NewChatOpened", schema([:])),
        ]
    }()

    /// The top screen's actions: the list's own, or only `Back` on a pushed screen.
    public var currentActions: [(name: String, input: JSON)] { stack.isEmpty ? Self.actions : [Self.back] }

    private static func name(_ destination: ChatsDestination<String>) -> String {
        switch destination {
        case .chat: "Chat"
        case .archived: "ArchivedChats"
        case .newChat: "NewChat"
        }
    }

    public mutating func perform(_ action: String, input: [String: JSON]) -> Result<Void, ErrorCode> {
        guard stack.isEmpty else {
            guard action == Self.back.name else { return .failure(.unknownAction) }
            stack.removeLast()
            return .success(())
        }
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
                switch chatId {
                case .string, .null: break
                default: return .failure(.badInput)
                }
            }
            model.beginSelection()
        case "SelectionToggled":
            guard case .string(let id)? = input["chatId"] else { return .failure(.badInput) }
            model.toggle(id)
        case "SelectionEnded":
            model.endSelection()
        case "ChatOpened":
            guard case .string(let id)? = input["chatId"] else { return .failure(.badInput) }
            stack.append(model.openChat(id))
        case "ArchivedOpened":
            stack.append(model.openArchived())
        case "NewChatOpened":
            stack.append(model.openNewChat())
        default:
            return .failure(.unknownAction)
        }
        return .success(())
    }

    // MARK: - State

    /// The state keys in `behaviors/chats/README.md` that iOS computes in the model. `chats` and
    /// `canReadAll` need `Conversation` and the controller, so they are absent.
    public func state() -> [String: JSON] {
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
        if let p = model.projection {
            state["chips"] = .object(Dictionary(uniqueKeysWithValues: ChatListFilter.allCases.map { ($0.rawValue, ids($0.ids(in: p))) }))
            state["unreadChipCount"] = .number(Double(p.unreadChipCount))
            state["groupsChipCount"] = .number(Double(p.groupsChipCount))
            state["archivedRowCount"] = .number(Double(p.archivedRowCount))
            state["tabBadge"] = .number(Double(p.tabBadge))
        }
        return state
    }

    private func node() -> JSON {
        let state: [String: JSON]
        switch stack.last {
        case nil: state = self.state()
        case .chat(let id)?: state = ["chatId": .string(id)]
        case .archived?, .newChat?: state = [:]
        }
        return .object([
            "name": .string(path.last!),
            "state": .object(state),
            "actions": .array(currentActions.map { .object(["name": .string($0.name), "input": $0.input]) }),
        ])
    }

    // MARK: - Requests

    /// Answers one request object: `ls`, `do`, `launch` or `reset`.
    public mutating func handle(_ request: JSON) -> JSON {
        guard case .object(let req) = request, case .string(let cmd)? = req["cmd"] else {
            return Self.error(.badRequest, "a request is an object with a cmd")
        }
        if case .array(let requested)? = req["path"], requested != path.map(JSON.string) {
            return Self.error(.badRequest, "no node at \(JSON.array(requested))")
        }
        switch cmd {
        case "ls":
            break
        case "launch":
            switch req["route"] {
            case nil, .null?: break
            case .string(Self.route)?: break
            case .string(let other)?: return Self.error(.badInput, "This host launches only \(Self.route), not \(other)")
            default: return Self.error(.badRequest, "route must be a string")
            }
            self = ChatsPuppetHost()
        case "reset":
            self = ChatsPuppetHost()
        case "do":
            guard case .string(let action)? = req["action"] else {
                return Self.error(.badRequest, "do needs an action")
            }
            var input: [String: JSON] = [:]
            switch req["input"] {
            case nil, .null?: break
            case .object(let o)?: input = o
            default: return Self.error(.badRequest, "input must be an object")
            }
            if case .failure(let code) = perform(action, input: input) {
                switch code {
                case .unknownAction:
                    return .object([
                        "ok": .bool(false),
                        "error": .object([
                            "code": .string(code.rawValue),
                            "message": .string("\(path.last!) has no action \(action)"),
                            "actions": .array(currentActions.map { .string($0.name) }),
                        ]),
                    ])
                case .badInput:
                    let schema = currentActions.first { $0.name == action }?.input ?? .null
                    return .object([
                        "ok": .bool(false),
                        "error": .object([
                            "code": .string(code.rawValue),
                            "message": .string("input doesn't match \(action)'s schema"),
                            "schema": schema,
                        ]),
                    ])
                case .badRequest:
                    return Self.error(code, "bad request")
                }
            }
        default:
            return Self.error(.badRequest, "unknown cmd \(cmd)")
        }
        return .object(["ok": .bool(true), "path": .array(path.map(JSON.string)), "node": node()])
    }

    /// Answers one request line with one response line.
    public mutating func handle(line: String) -> String {
        let response: JSON
        if let request = try? JSONDecoder().decode(JSON.self, from: Data(line.utf8)) {
            response = handle(request)
        } else {
            response = Self.error(.badRequest, "not JSON")
        }
        let data = (try? JSONEncoder().encode(response)) ?? Data(#"{"ok":false}"#.utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func error(_ code: ErrorCode, _ message: String) -> JSON {
        .object(["ok": .bool(false), "error": .object(["code": .string(code.rawValue), "message": .string(message)])])
    }
}

/// A JSON value, compared exactly: a boolean never equals a number.
public enum JSON: Codable, Equatable, Sendable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public var description: String {
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
