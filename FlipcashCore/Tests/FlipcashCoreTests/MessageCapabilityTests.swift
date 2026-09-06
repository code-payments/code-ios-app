//
//  MessageCapabilityTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore
import FlipcashAPI

@Suite("Message capabilities")
struct MessageCapabilityTests {

    private let me = UUID()
    private let them = UUID()
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func text(_ body: String, from sender: UUID, eventSequence: UInt64 = 1, sentAgo: TimeInterval = 0) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: 1), senderID: sender, content: .text(body),
            date: now.addingTimeInterval(-sentAgo), unreadSeq: 1, eventSequence: eventSequence
        )
    }

    private func resolve(_ message: ConversationMessage, policy: MessagePolicy = .default) -> Set<MessageCapability> {
        MessageCapability.resolve(for: message, in: nil, as: me, policy: policy, now: now)
    }

    @Test("My own confirmed text can be copied, edited, and deleted")
    func ownTextIsFullyActionable() {
        #expect(resolve(text("hi", from: me)) == [.copy, .reply, .edit, .delete])
    }

    @Test("An unconfirmed message of mine offers nothing — it has no sequence to send as expected")
    func unconfirmedMessageOffersNothing() {
        #expect(resolve(text("hi", from: me, eventSequence: 0)).isEmpty)
    }

    @Test("Someone else's text can only be copied")
    func otherPersonsTextIsCopyOnly() {
        #expect(resolve(text("hi", from: them)) == [.copy, .reply])
    }

    @Test("A tombstone offers nothing")
    func tombstoneOffersNothing() {
        let tombstone = ConversationMessage(
            id: MessageID(value: 2), senderID: me,
            content: .deleted(.init(deletedBy: me, deletedAt: now)),
            date: now, unreadSeq: 1, eventSequence: 3
        )
        #expect(resolve(tombstone).isEmpty)
    }

    @Test("A cash message offers Reply and nothing else")
    func cashMessageOffersReplyOnly() {
        let cash = ConversationMessage(
            id: MessageID(value: 3), senderID: me,
            content: .cash(ExchangedFiat(nativeAmount: .usd(20), rate: .oneToOne)),
            cashAction: .sent, date: now, unreadSeq: 1, eventSequence: 2
        )
        #expect(resolve(cash) == [.reply])
    }

    // MARK: - Windows -

    private func windows(edit: TimeInterval?, delete: TimeInterval?) -> MessagePolicy {
        MessagePolicy(editWindow: edit, deleteWindow: delete, deletedPresentation: .placeholder)
    }

    @Test("A message inside both windows keeps every action")
    func messageInsideBothWindowsIsFullyActionable() {
        let policy = windows(edit: 900, delete: 172_800)
        #expect(resolve(text("hi", from: me, sentAgo: 600), policy: policy) == [.copy, .reply, .edit, .delete])
    }

    @Test("A message past the edit window but inside the delete window can still be deleted")
    func messagePastEditWindowIsDeleteOnly() {
        let policy = windows(edit: 900, delete: 172_800)
        #expect(resolve(text("hi", from: me, sentAgo: 1_200), policy: policy) == [.copy, .reply, .delete])
    }

    @Test("A message past both windows can only be copied")
    func messagePastBothWindowsIsCopyOnly() {
        let policy = windows(edit: 900, delete: 172_800)
        #expect(resolve(text("hi", from: me, sentAgo: 200_000), policy: policy) == [.copy, .reply])
    }

    @Test("A message past the delete window loses delete even while it is still editable")
    func deleteWindowGatesIndependentlyOfEdit() {
        // A delete window shorter than the edit window is not the configuration we ship, but it is
        // what proves the two gates are independent rather than one implying the other.
        let policy = windows(edit: 900, delete: 60)
        #expect(resolve(text("hi", from: me, sentAgo: 300), policy: policy) == [.copy, .reply, .edit])
    }

    @Test("At exactly the window length both actions are still offered — the boundary is inclusive")
    func boundaryIsInclusive() {
        let policy = windows(edit: 900, delete: 172_800)
        #expect(resolve(text("hi", from: me, sentAgo: 900), policy: policy) == [.copy, .reply, .edit, .delete])
        #expect(resolve(text("hi", from: me, sentAgo: 172_800), policy: policy) == [.copy, .reply, .delete])
    }

    @Test("A hair past the boundary the action is gone")
    func justPastBoundaryDropsTheAction() {
        let policy = windows(edit: 900, delete: 172_800)
        #expect(resolve(text("hi", from: me, sentAgo: 900.001), policy: policy) == [.copy, .reply, .delete])
        #expect(resolve(text("hi", from: me, sentAgo: 172_800.001), policy: policy) == [.copy, .reply])
    }

    @Test("A nil window never lapses")
    func nilWindowNeverLapses() {
        let policy = windows(edit: nil, delete: nil)
        #expect(resolve(text("hi", from: me, sentAgo: 10_000_000), policy: policy) == [.copy, .reply, .edit, .delete])
    }

    // MARK: - Fallbacks -

    @Test("Flags that carry no windows fall back to 15 minutes and 48 hours")
    func unsetFlagsFallBackToTheAgreedWindows() {
        let policy = MessagePolicy(userFlags: nil)
        #expect(policy.editWindow == 900)
        #expect(policy.deleteWindow == 172_800)
        #expect(MessagePolicy.fallbackEditWindow == 900)
        #expect(MessagePolicy.fallbackDeleteWindow == 172_800)
    }

    @Test("Absent flags — a failed or pending fetch — gate the same as flags with unset windows")
    func absentFlagsGateLikeUnsetWindows() {
        // `Session.userFlags` is nil until a cached row is restored, and a failed fetch never
        // assigns — so this is the no-flags path, and it must not be more permissive than the
        // fallback.
        let policy = MessagePolicy(userFlags: nil)
        #expect(resolve(text("hi", from: me, sentAgo: 600), policy: policy) == [.copy, .reply, .edit, .delete])
        #expect(resolve(text("hi", from: me, sentAgo: 1_200), policy: policy) == [.copy, .reply, .delete])
        #expect(resolve(text("hi", from: me, sentAgo: 200_000), policy: policy) == [.copy, .reply])
    }

    @Test("Flags that arrived with both windows unset fall back too")
    func presentFlagsWithUnsetWindowsFallBack() {
        let flags = UserFlags(Flipcash_Account_V1_UserFlags())
        #expect(flags.messageEditWindow == nil)
        #expect(flags.messageDeleteWindow == nil)

        let policy = MessagePolicy(userFlags: flags)
        #expect(policy.editWindow == MessagePolicy.fallbackEditWindow)
        #expect(policy.deleteWindow == MessagePolicy.fallbackDeleteWindow)
    }

    @Test("Windows the server did send are used as-is, not replaced by the fallbacks")
    func serverWindowsWin() {
        let flags = UserFlags(Flipcash_Account_V1_UserFlags.with {
            $0.messageEditWindow = .with { $0.seconds = 60 }
            $0.messageDeleteWindow = .with { $0.seconds = 120 }
        })
        let policy = MessagePolicy(userFlags: flags)
        #expect(policy.editWindow == 60)
        #expect(policy.deleteWindow == 120)
        #expect(resolve(text("hi", from: me, sentAgo: 90), policy: policy) == [.copy, .reply, .delete])
    }

    @Test("The default policy is the fallback policy")
    func defaultPolicyCarriesTheFallbacks() {
        #expect(MessagePolicy.default.editWindow == MessagePolicy.fallbackEditWindow)
        #expect(MessagePolicy.default.deleteWindow == MessagePolicy.fallbackDeleteWindow)
        #expect(resolve(text("hi", from: me, sentAgo: 86_400)) == [.copy, .reply, .delete])
    }

    // MARK: - Expiry scheduling -

    @Test("The next expiry is the soonest window still ahead of now")
    func nextExpiryIsTheSoonestDeadline() {
        let policy = windows(edit: 900, delete: 172_800)
        let recent = text("recent", from: me, sentAgo: 60)
        let older = text("older", from: me, sentAgo: 300)
        let expiry = MessageCapability.nextExpiry(
            among: [recent, older], in: nil, as: me, policy: policy, now: now
        )
        // `older` loses edit first: sent 300s ago, so 600s from now.
        #expect(expiry == older.date.addingTimeInterval(900))
    }

    @Test("A deadline landing exactly on now is still scheduled — the capability is granted at that instant")
    func deadlineExactlyAtNowIsScheduled() {
        // `resolve` grants edit at exactly the window's length, so the deadline that takes it away
        // has to survive `nextExpiry` too; dropping it would leave Edit on the row with no timer to
        // remove it. The delete deadline is still far ahead, so only the inclusive edit boundary can
        // produce this answer.
        let policy = windows(edit: 900, delete: 172_800)
        let message = text("hi", from: me, sentAgo: 900)
        #expect(resolve(message, policy: policy).contains(.edit))
        #expect(MessageCapability.nextExpiry(
            among: [message], in: nil, as: me, policy: policy, now: now
        ) == now)
    }

    @Test("A message whose windows have all lapsed schedules nothing")
    func fullyLapsedMessageSchedulesNothing() {
        let policy = windows(edit: 900, delete: 172_800)
        let expiry = MessageCapability.nextExpiry(
            among: [text("old", from: me, sentAgo: 200_000)], in: nil, as: me, policy: policy, now: now
        )
        #expect(expiry == nil)
    }

    @Test("Messages with nothing to lose contribute no deadline")
    func nonExpiringMessagesScheduleNothing() {
        let policy = windows(edit: 900, delete: 172_800)
        let theirs = text("hi", from: them)
        let unconfirmed = text("hi", from: me, eventSequence: 0)
        #expect(MessageCapability.nextExpiry(
            among: [theirs, unconfirmed], in: nil, as: me, policy: policy, now: now
        ) == nil)
    }

    @Test("An unbounded policy schedules nothing — there is no deadline to wake for")
    func unboundedPolicySchedulesNothing() {
        #expect(MessageCapability.nextExpiry(
            among: [text("hi", from: me)], in: nil, as: me, policy: windows(edit: nil, delete: nil), now: now
        ) == nil)
    }
}
