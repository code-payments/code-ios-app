//
//  GroupPushRoutingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashAPI
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// A push tap and an invite link are two entry points into one routing decision: both carry the
/// same chat id, and for a group the signed-in user has not joined both must land on the gated
/// transcript rather than on a join-only detour.
@MainActor
@Suite("Group push routing")
struct GroupPushRoutingTests {

    /// The group's id in its contract form — 16 bytes, which is what makes it expressible as a UUID
    /// in a link (`common.v1.ChatId.value`).
    private static let groupUUID = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!

    /// How that id spells itself in a link — `ConversationID.linkPathComponent` lowercases.
    private static let groupPath = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"

    private func groupID() throws -> ConversationID {
        try #require(ConversationID(uuidString: Self.groupUUID.uuidString))
    }

    /// A CHAT push aimed at `conversationID`, in the shape `NotificationPayload` decodes: the
    /// serialized `push.v1.Payload` base64'd under the APS custom-data key.
    private func chatPush(for conversationID: ConversationID, type: Flipcash_Chat_V1_ChatType = .group) throws -> [AnyHashable: Any] {
        let payload = Flipcash_Push_V1_Payload.with {
            $0.category = .chat
            $0.navigation = .with { $0.chatID = conversationID.proto }
            $0.chatMetadata = .with { $0.type = type }
        }
        return ["aps": [NotificationPayload.userInfoKey: try payload.serializedData().base64EncodedString()]]
    }

    /// Stands in for `Session` on the gate's read side.
    private final class StubHoldings: ConversationGateReading {
        var isStaff = false
        var totalBalance = ExchangedFiat(nativeAmount: .usd(0), rate: Rate(fx: 1, currency: .usd))
        private let balances: [PublicKey: StoredBalance]

        init(balances: [PublicKey: StoredBalance] = [:]) {
            self.balances = balances
        }

        func balance(for mint: PublicKey) -> StoredBalance? { balances[mint] }
    }

    private func holding(usd: Decimal) throws -> StoredBalance {
        try StoredBalance(
            quarks: NSDecimalNumber(decimal: usd * 1_000_000).uint64Value,
            symbol: "USDF",
            name: "USDF Coin",
            supplyFromBonding: nil,
            sellFeeBps: nil,
            mint: .usdf,
            vmAuthority: nil,
            updatedAt: Date(),
            imageURL: nil,
            costBasis: 0
        )
    }

    // MARK: - Push tap → route

    @Test("A group push decodes to its chat id and taps through to the chat route")
    func pushTapRoutesToTheChat() throws {
        let conversationID = try groupID()
        let userInfo = try chatPush(for: conversationID)

        #expect(NotificationPayload.chatID(userInfo) == conversationID)
        #expect(NotificationPayload.chatType(userInfo) == .group)

        let tapped = try #require(NotificationPayload.chatID(userInfo))
        let url = URL.chatDeepLink(for: tapped)
        #expect(url.absoluteString == "flipcash://chat/\(Self.groupPath)")

        guard case .chat(let parsed) = Route(url: url)?.path else {
            Issue.record("A chat push's deep link should parse as .chat")
            return
        }
        #expect(parsed == conversationID)
    }

    @Test("The push tap and the invite link resolve to the same destination")
    func pushAndInviteShareOneDestination() throws {
        let conversationID = try groupID()
        let fromPush = try #require(NotificationPayload.chatID(try chatPush(for: conversationID)))

        // `Route.Path` isn't Equatable, so the two are compared by what they carry.
        guard case .chat(let fromTap) = Route(url: URL.chatDeepLink(for: fromPush))?.path,
              case .chat(let fromInvite) = Route(url: URL.groupChatInvite(for: conversationID))?.path
        else {
            Issue.record("Both entry points should parse as .chat")
            return
        }
        #expect(fromTap == fromInvite)
        #expect(fromTap == conversationID)

        // `.group` is routed whether or not the viewer is a member — the screen gates itself.
        #expect(
            DeepLinkAction.chatDestination(for: .group, conversationID: conversationID)
                == .tipConversation(conversationID)
        )
        #expect(DeepLinkAction.chatDestination(for: .contactDm, conversationID: conversationID) == nil)
        #expect(DeepLinkAction.chatDestination(for: nil, conversationID: conversationID) == nil)
    }

    @Test("The Send Cash action keeps its own path off the same id")
    func sendCashActionKeepsItsPath() throws {
        let conversationID = try groupID()
        let url = URL.chatDeepLink(for: conversationID, sendCash: true)
        #expect(url.absoluteString == "flipcash://chat/\(Self.groupPath)/send")

        guard case .chatSendCash(let parsed) = Route(url: url)?.path else {
            Issue.record("The Send Cash action should parse as .chatSendCash")
            return
        }
        #expect(parsed == conversationID)
    }

    // MARK: - What the destination shows a non-member

    @Test("An unjoined group whose bar the viewer is under lands blurred, not readable")
    func unjoinedAndShortLandsGated() throws {
        let rules = ConversationRules(listener: [.minimumBalance(MinimumBalanceRequirement(amount: .usd(100), mints: [.usdf]))])
        let session = StubHoldings(balances: [.usdf: try holding(usd: 25)])
        let gate = conversationGate(session: session, rules: rules, rates: [:])

        let presentation = conversationGatePresentation(gate, isMember: false)
        #expect(presentation == .blocked(.minimumBalance(amount: .usd(100), mint: .usdf)))
        #expect(presentation.obscuresTranscript)
        #expect(presentation.replacesComposer)
    }

    @Test("An unjoined group whose bar the viewer clears offers the join, still blurred")
    func unjoinedAndClearLandsOnJoin() throws {
        let requirement = MinimumBalanceRequirement(amount: .usd(100), mints: [.usdf])
        let rules = ConversationRules(listener: [.minimumBalance(requirement)])
        let session = StubHoldings(balances: [.usdf: try holding(usd: 150)])
        let gate = conversationGate(session: session, rules: rules, rates: [:])

        // Clearing the bar changes what the panel offers, not what the viewer can read:
        // joining is what unblurs.
        let presentation = conversationGatePresentation(gate, isMember: false)
        #expect(presentation == .join(.minimumBalance(amount: .usd(100), mint: .usdf)))
        #expect(presentation.obscuresTranscript)
        #expect(presentation.replacesComposer)
    }
}
