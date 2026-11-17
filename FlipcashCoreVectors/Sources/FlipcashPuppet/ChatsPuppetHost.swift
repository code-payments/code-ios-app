//
//  ChatsPuppetHost.swift
//  FlipcashPuppet
//

import Foundation
import FlipcashCore
import FlipcashStore

/// The Chats screen as a Puppet session: the seeded ``ChatsModel`` behind the request and response
/// shapes in the orchestrator's `docs/puppet/PROTOCOL.md`. ``FlipcashPuppetHost`` starts one for
/// each `launch` of ``route`` and hands it every other request.
///
/// ``ChatsModel`` is synchronous and reads no services, so there is nothing to settle before a
/// reply and nothing for a fixture guard to catch.
///
/// Opening the archive pushes a hosted screen: its list is the projection's ``ChatListProjection/archived``,
/// which is what `ConversationController.archivedConversations` reads. `Unarchive` calls
/// ``ChatArchiveFile/unarchive(_:)``, the record `ChatArchiveStore` writes, and projects the seed
/// again from its ``ChatArchiveFile/archivedIDs``, as the controller does when its archive changes.
///
/// Opening New Chat pushes its hosted chooser, whose rows ask ``NewChat/choose(_:balances:)`` over
/// ``balances``, the launched seed's balances as `Session.balances(for:)` gives them. The "No Community
/// Currencies" dialog shows as a screen above New Chat.
public struct ChatsPuppetHost: PuppetSession {

    public enum ErrorCode: String, Error {
        case badRequest = "bad_request"
        case unknownAction = "unknown_action"
        case badInput = "bad_input"
    }

    public static let screen = "Chats"

    /// The only route `launch` accepts: the Chats tab, in the form both apps' deep links use.
    public static let route = "/tab/chats"

    private var model = ChatsModel<String>()

    /// The archived chats, in the record the app's `ChatArchiveStore` keeps.
    private var archive = ChatArchiveFile(archived: [ChatArchiveFile.key(Self.conversationID(Self.id("05"))!): .distantPast])

    /// A screen above the list.
    private enum Screen: Equatable {
        case chats(ChatsDestination<String>)
        case newChat(NewChat.Destination)
        case noCommunityCurrencies
    }

    /// Screens pushed over the list. Archived and New Chat are hosted; the rest show their name
    /// and lend `Back`.
    private var stack: [Screen] = []

    /// The seed a launch gets when it names none.
    public static let defaultSeed = "default"

    /// The seeds a launch can name: the chats are the same in each, the balances New Chat reads
    /// differ. The shared Chats README lists what each one holds.
    public static let seeds: [String: [ExchangedBalance]] = [
        defaultSeed: [dollars].exchanged(with: .oneToOne),
        "community-holder": [dollars, puppet].exchanged(with: .oneToOne),
    ]

    /// $25 of dollars.
    private static let dollars = try! StoredBalance(
        quarks: 25_000_000, symbol: "USDF", name: "USDF", supplyFromBonding: nil, sellFeeBps: nil,
        mint: .usdf, vmAuthority: nil, updatedAt: .distantPast, imageURL: nil, costBasis: 0
    )

    /// $5 of one launchpad community currency: 208 tokens, valued on its bonding curve.
    private static let puppet = try! StoredBalance(
        quarks: 208 * 10_000_000_000, symbol: "PUPPET", name: "Puppet",
        supplyFromBonding: 1_000_000 * 10_000_000_000, sellFeeBps: nil,
        mint: try! PublicKey([UInt8](repeating: 7, count: 32)), vmAuthority: nil,
        updatedAt: .distantPast, imageURL: nil, costBasis: 0
    )

    /// The launched seed's balances, as `Session.balances(for:)` gives them.
    private let balances: [ExchangedBalance]

    /// The screen names from the list to the top screen.
    public var path: [String] { [Self.screen] + stack.map(Self.name) }

    /// Starts the list over `seed`, one of ``seeds``.
    public init(seed: String = defaultSeed) {
        balances = Self.seeds[seed] ?? Self.seeds[Self.defaultSeed]!
        project()
    }

    private mutating func project() {
        let archived = Set(archive.archivedIDs.map { $0.data.map { String(format: "%02x", $0) }.joined() })
        model.update(.project(Self.seed(archived: archived)))
    }

    private static func id(_ prefix: String) -> String { String(repeating: prefix, count: 16) }

    /// The seed's 32-hex-character chat id as the app's ``ConversationID``, or `nil` if it isn't hex.
    static func conversationID(_ hex: String) -> ConversationID? {
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return ConversationID(data: Data(bytes))
    }

    /// The seed table in `behaviors/chats/README.md`, newest first, with `archived` marked archived.
    static func seed(archived: Set<String>) -> [ChatListEntry<String>] {
        func entry(_ id: String, _ type: ConversationType, unread: Int, age: Int) -> ChatListEntry<String> {
            ChatListEntry(
                id: id,
                type: type,
                lastActivity: Date(timeIntervalSince1970: TimeInterval(1_000_000 - age)),
                isArchived: archived.contains(id),
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
            entry(id("05"), .group, unread: 2, age: 5),
        ]
    }

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

    /// The archive's actions. Its select mode is Android-only, so `Unarchive` is the one shared action.
    public static let archivedActions: [(name: String, input: JSON)] = [
        ("Unarchive", schema(["chatId": .object(["type": .string("string"), "format": .string("ChatId")])], required: ["chatId"])),
    ]

    /// New Chat's rows.
    public static let newChatActions: [(name: String, input: JSON)] = [
        ("FindByUsernameOpened", schema([:])),
        ("PrivateGroupOpened", schema([:])),
        ("CommunityGroupOpened", schema([:])),
    ]

    /// The top screen's actions: the list's own, a hosted screen's, or only `Back` on a screen that isn't hosted.
    public var currentActions: [(name: String, input: JSON)] {
        switch stack.last {
        case nil: Self.actions
        case .chats(.archived)?: Self.archivedActions + [Self.back]
        case .chats(.newChat)?: Self.newChatActions + [Self.back]
        case .noCommunityCurrencies?: [("ExploreCurrenciesOpened", Self.schema([:])), Self.back]
        case .chats(.chat)?, .newChat?: [Self.back]
        }
    }

    private static func name(_ screen: Screen) -> String {
        switch screen {
        case .chats(.chat): "Chat"
        case .chats(.archived): "ArchivedChats"
        case .chats(.newChat): "NewChat"
        case .newChat(.usernameLookup): "FindByUsername"
        case .newChat(.newPrivateGroup): "NewPrivateGroup"
        case .newChat(.newPublicGroup): "NewCommunityGroup"
        case .newChat(.discoverCurrencies): "DiscoverCurrencies"
        case .noCommunityCurrencies: "NoCommunityCurrencies"
        }
    }

    private mutating func choose(_ choice: NewChat.Choice) {
        switch NewChat.choose(choice, balances: balances) {
        case .open(let destination): stack.append(.newChat(destination))
        case .noCommunityCurrencies: stack.append(.noCommunityCurrencies)
        }
    }

    public mutating func perform(_ action: String, input: [String: JSON]) -> Result<Void, ErrorCode> {
        if let top = stack.last {
            switch (top, action) {
            case (_, Self.back.name):
                stack.removeLast()
            case (.chats(.newChat), "FindByUsernameOpened"):
                choose(.findByUsername)
            case (.chats(.newChat), "PrivateGroupOpened"):
                choose(.privateGroup)
            case (.chats(.newChat), "CommunityGroupOpened"):
                choose(.communityGroup)
            case (.noCommunityCurrencies, "ExploreCurrenciesOpened"):
                stack.removeLast()
                stack.append(.newChat(NewChat.explore))
            case (.chats(.archived), "Unarchive"):
                guard case .string(let hex)? = input["chatId"], let id = Self.conversationID(hex) else { return .failure(.badInput) }
                archive.unarchive(id)
                project()
            default:
                return .failure(.unknownAction)
            }
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
            stack.append(.chats(model.openChat(id)))
        case "ArchivedOpened":
            stack.append(.chats(model.openArchived()))
        case "NewChatOpened":
            stack.append(.chats(model.openNewChat()))
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
        case .chats(.chat(let id))?: state = ["chatId": .string(id)]
        case .chats(.archived)?: state = [
            "loading": .bool(model.isLoading),
            "chatIds": .array((model.projection?.archived ?? []).map(JSON.string)),
        ]
        case .chats(.newChat)?, .newChat?, .noCommunityCurrencies?: state = [:]
        }
        return .object([
            "name": .string(path.last!),
            "state": .object(state),
            "actions": .array(currentActions.map { .object(["name": .string($0.name), "input": $0.input]) }),
        ])
    }

    // MARK: - Requests

    /// Answers one request object: `ls` or `do`. ``FlipcashPuppetHost`` answers `launch` and `reset`.
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

    static func error(_ code: ErrorCode, _ message: String) -> JSON {
        .object(["ok": .bool(false), "error": .object(["code": .string(code.rawValue), "message": .string(message)])])
    }
}
