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

    private static let ana = [ConversationMember(userID: me, displayName: "Me"), ConversationMember(userID: other, displayName: "Ana")]

    private static func conversation(
        type: ConversationType,
        isPrivate: Bool = false,
        rules: ConversationRules? = nil,
        members: [ConversationMember] = ana
    ) -> Conversation {
        Conversation(
            id: chatID,
            members: members,
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
        message: Result<ConversationMessage?, any Error>,
        known: ConversationMember? = nil,
        cashLinks: @escaping @Sendable (String) async throws -> LinkCard.Cash.Resolved = { _ in throw Offline() }
    ) async throws -> LinkCard.Message.State {
        let viewer = MessageLinkViewer(
            conversation: { _ in held },
            isMember: { _ in member },
            title: { _ in "Moony" },
            knownMember: { _ in known },
            userID: me
        )
        let lookup = LinkCardResolver.messageLookup(
            chats: Chats(result: chat), messages: Messages(result: message), mints: Mints(), owner: owner, viewer: viewer, cashLinks: cashLinks
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

    @Test func aRosterMemberWithNoDisplayNameIsNamedByUsername() async throws {
        let members = [ConversationMember(userID: Self.other, displayName: "", username: Username("ana"))]
        let state = try await Self.state(
            held: Self.conversation(type: .group, members: members), member: true, message: .success(Self.message(.text("hello")))
        )
        guard case .resolved(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.authorName == "@ana")
    }

    @Test func aSenderTheRosterLeavesOutIsNamedByTheKnownAuthors() async throws {
        let state = try await Self.state(
            held: Self.conversation(type: .group, members: []),
            member: true,
            message: .success(Self.message(.text("hello"))),
            known: ConversationMember(userID: Self.other, displayName: "Ted")
        )
        guard case .resolved(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.authorName == "Ted")
    }

    @Test func aSenderNobodyCanNameIsSomeone() async throws {
        let state = try await Self.state(
            held: Self.conversation(type: .group, members: []), member: true, message: .success(Self.message(.text("hello")))
        )
        guard case .resolved(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.authorName == "Someone")
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

    private static let photo = MediaAttachment(blobID: BlobID(data: Data(repeating: 7, count: 16)), width: 4, height: 3, blurhash: "LEHV6nWB2yk8")

    @Test func aMemberSeesThePhotoWithItsBlob() async throws {
        let state = try await Self.state(
            held: Self.conversation(type: .group), member: true, message: .success(Self.message(.media([Self.photo], caption: nil)))
        )
        guard case .resolved(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.excerpt.isEmpty)
        #expect(value.photo == LinkCard.Message.Photo(blobID: Self.photo.blobID, sealed: nil, blurHash: "LEHV6nWB2yk8"))
    }

    @Test func aRedactedPhotoCarriesOnlyItsBlurHash() async throws {
        let state = try await Self.state(
            held: Self.conversation(type: .group, rules: Self.gate), member: false,
            message: .success(Self.message(.media([Self.photo], caption: "secret"), redacted: true))
        )
        guard case .gatedRedacted(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.photoBlurHash == "LEHV6nWB2yk8")
        #expect(!"\(state)".contains("secret"))
    }

    @Test func aTextThatIsOnlyACashLinkIsDrawnAsCash() async throws {
        let state = try await Self.state(
            held: Self.conversation(type: .group), member: true,
            message: .success(Self.message(.text("https://send.flipcash.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW"))),
            cashLinks: { _ in LinkCard.Cash.Resolved(amount: "$1.00", claim: .claimed, tokenName: "USDF", iconURL: nil) }
        )
        guard case .cash(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.verb == .cashLink)
        #expect(value.amount == "$1.00")
        #expect(value.claim == .claimed)
    }

    @Test func aCashLinkWithMoreTextStaysAnExcerpt() async throws {
        let text = "here you go https://send.flipcash.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW"
        let state = try await Self.state(
            held: Self.conversation(type: .group), member: true, message: .success(Self.message(.text(text))),
            cashLinks: { _ in LinkCard.Cash.Resolved(amount: "$1.00", claim: .claimed, tokenName: "USDF", iconURL: nil) }
        )
        guard case .resolved(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.excerpt == text)
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

    @Test func aMissingChatIsUnavailable() async throws {
        let noChat = try await Self.state(held: nil, member: false, chat: .failure(ErrorGetChat.notFound), message: .failure(Offline()))
        #expect(noChat == .unavailable)
    }

    @Test func aGoneMessageInAKnownChatKeepsTheChatHeader() async throws {
        let nilMessage = try await Self.state(held: Self.conversation(type: .group), member: true, message: .success(nil))
        #expect(nilMessage == .deleted(.init(chatTitle: "Moony", kind: .publicGroup, avatarID: Self.chatID.description)))

        let tombstone = try await Self.state(
            held: Self.conversation(type: .contactDm), member: true,
            message: .success(Self.message(.deleted(.init(deletedBy: nil, deletedAt: Date(timeIntervalSince1970: 0)))))
        )
        guard case .deleted(let value) = tombstone else { Issue.record("got \(tombstone)"); return }
        #expect(value.kind == .directMessage)
    }

    @Test func theKindFollowsTheChat() async throws {
        let state = try await Self.state(held: Self.conversation(type: .group, isPrivate: true), member: true, message: .success(Self.message(.text("hi"))))
        guard case .resolved(let value) = state else { Issue.record("got \(state)"); return }
        #expect(value.kind == .privateGroup)
    }
}
