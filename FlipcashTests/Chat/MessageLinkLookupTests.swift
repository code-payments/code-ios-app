import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite struct MessageLinkLookupTests {

    private static let chatID = ConversationID(uuidString: "6f1c3a9e-2b7d-4e0a-9c55-1d2e3f405162")!
    private static let me = UUID()
    private static let other = UUID()
    private static let owner = KeyPair.generate()!

    private static let card = LinkCard.Message(
        url: URL(string: "https://app.flipcash.com/chat/\(chatID.description)/m/7")!,
        chatID: chatID,
        messageID: MessageID(value: 7),
        range: NSRange(location: 0, length: 60)
    )

    private struct Offline: Error {}

    private struct Chats: GroupChatReading {
        var result: Result<Conversation, any Error>
        func getChat(owner: KeyPair, conversationID: ConversationID, viewMode: ConversationViewMode) async throws -> Conversation {
            try result.get()
        }
    }

    private struct Messages: MessageLinkReading {
        var result: Result<ConversationMessage?, any Error>
        func getMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, viewMode: ConversationViewMode) async throws -> ConversationMessage? {
            try result.get()
        }
    }

    private struct Mints: MintMetadataReading {
        func fetchMint(mint: PublicKey) async throws -> MintMetadata { throw Offline() }
    }

    private static func conversation(type: ConversationType, isPrivate: Bool = false, rules: ConversationRules? = nil) -> Conversation {
        Conversation(
            id: chatID,
            members: [
                ConversationMember(userID: me, displayName: "Me"),
                ConversationMember(userID: other, displayName: "Ana"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: type,
            title: "Moony",
            rules: rules,
            creator: other,
            isPrivate: isPrivate
        )
    }

    private static func message(_ content: ConversationMessage.Content, redacted: Bool = false) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: 7),
            senderID: other,
            content: content,
            date: Date(timeIntervalSince1970: 0),
            unreadSeq: 0,
            redacted: redacted
        )
    }

    private static func state(
        held: Conversation?,
        member: Bool,
        chat: Result<Conversation, any Error> = .failure(Offline()),
        message: Result<ConversationMessage?, any Error>
    ) async throws -> LinkCard.Message.State {
        let viewer = MessageLinkViewer(
            conversation: { _ in held },
            isMember: { _ in member },
            title: { _ in "Moony" },
            userID: me
        )
        let lookup = LinkCardResolver.messageLookup(
            chats: Chats(result: chat), messages: Messages(result: message), mints: Mints(), owner: owner, viewer: viewer
        )
        return try await lookup(card)
    }

    private static let gate = ConversationRules(listener: [
        .minimumBalance(MinimumBalanceRequirement(amount: .usd(10), mints: [.usdf])),
    ])

    @Test func aMemberOfAPublicGroupReadsTheMessage() async throws {
        let state = try await Self.state(held: Self.conversation(type: .group), member: true, message: .success(Self.message(.text("hello"))))
        guard case .resolved(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.excerpt == "hello")
        #expect(value.authorName == "Ana")
    }

    @Test func aNonMemberWhoMeetsTheRulesGetsTheExcerptAndJoin() async throws {
        let state = try await Self.state(held: Self.conversation(type: .group), member: false, message: .success(Self.message(.text("hello"))))
        guard case .gatedReadable(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.excerpt == "hello")
    }

    @Test func aRedactedMessageCarriesNoTextAndTheRequirement() async throws {
        let state = try await Self.state(
            held: Self.conversation(type: .group, rules: Self.gate), member: false,
            message: .success(Self.message(.text("secret words"), redacted: true))
        )
        guard case .gatedRedacted(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.requirement == "Balance Requirement:\n$10")
        #expect(!"\(state)".contains("secret words"))
    }

    @Test func cashIsNeverRedactedForANonMember() async throws {
        let amount = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 15_000_000, mint: .usdf),
            nativeAmount: FiatAmount(value: 15, currency: .usd),
            currencyRate: Rate(fx: 1, currency: .usd)
        )
        let state = try await Self.state(held: Self.conversation(type: .group), member: false, message: .success(Self.message(.cash(amount))))
        guard case .cash(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.verb == .sent)
    }

    @Test func aNonMemberOfAPrivateGroupSeesTheLockedPreview() async throws {
        let state = try await Self.state(
            held: nil, member: false,
            chat: .success(Self.conversation(type: .group, isPrivate: true)),
            message: .failure(ErrorGetMessage.denied)
        )
        guard case .lockedGroup(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.title == "Moony")
        #expect(value.hostName == "Ana")
    }

    @Test func aDeniedDirectChatShowsOnlyItsKind() async throws {
        let state = try await Self.state(held: nil, member: false, chat: .failure(ErrorGetChat.denied), message: .failure(Offline()))
        #expect(state == .lockedDirect)
    }

    @Test func aDirectChatTheViewerIsInIsReadable() async throws {
        let state = try await Self.state(held: Self.conversation(type: .contactDm), member: true, message: .success(Self.message(.text("hi"))))
        guard case .resolved = state else { Issue.record("got \(state)"); return }
    }

    @Test func aMissingChatOrMessageIsUnavailable() async throws {
        let noChat = try await Self.state(held: nil, member: false, chat: .failure(ErrorGetChat.notFound), message: .failure(Offline()))
        #expect(noChat == .unavailable)
        let noMessage = try await Self.state(held: Self.conversation(type: .group), member: true, message: .success(nil))
        #expect(noMessage == .unavailable)
    }
}
