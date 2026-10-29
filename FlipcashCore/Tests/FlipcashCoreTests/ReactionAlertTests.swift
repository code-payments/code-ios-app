//
//  ReactionAlertTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import CoreGraphics
@testable import FlipcashCore

@Suite("ReactionAlertTrigger")
struct ReactionAlertTriggerTests {

    private static let me = UUID()
    private static let other = UUID()

    private static func update(actor: UserID = other, added: Bool = true, boosted: Bool = false) -> DecodedReactionUpdate {
        DecodedReactionUpdate(messageID: MessageID(value: 7), emoji: "🔥", actor: actor, added: added, boosted: boosted, count: 1, version: 1, reactedAt: nil)
    }

    @Test("An add by someone else in the foreground may qualify")
    func precheck_addByOther_passes() {
        #expect(ReactionAlertTrigger.precheck(Self.update(), selfUserID: Self.me, isForeground: true) == nil)
    }

    @Test("A boost by someone else in the foreground may qualify")
    func precheck_boostByOther_passes() {
        #expect(ReactionAlertTrigger.precheck(Self.update(boosted: true), selfUserID: Self.me, isForeground: true) == nil)
    }

    @Test("The user's own reaction, from another device, is dropped")
    func precheck_ownActor_drops() {
        #expect(ReactionAlertTrigger.precheck(Self.update(actor: Self.me), selfUserID: Self.me, isForeground: true) == .ownActor)
    }

    @Test("A removal shows nothing")
    func precheck_removed_drops() {
        #expect(ReactionAlertTrigger.precheck(Self.update(added: false), selfUserID: Self.me, isForeground: true) == .removed)
    }

    @Test("Nothing shows while the app is in the background")
    func precheck_background_drops() {
        #expect(ReactionAlertTrigger.precheck(Self.update(), selfUserID: Self.me, isForeground: false) == .background)
    }

    @Test("Background wins over every other reason")
    func precheck_backgroundFirst() {
        #expect(ReactionAlertTrigger.precheck(Self.update(actor: Self.me, added: false), selfUserID: Self.me, isForeground: false) == .background)
    }

    @Test("A message the user sent qualifies")
    func sender_self_passes() {
        #expect(ReactionAlertTrigger.checkSender(Self.me, selfUserID: Self.me) == nil)
    }

    @Test("A message someone else sent is dropped")
    func sender_other_drops() {
        #expect(ReactionAlertTrigger.checkSender(Self.other, selfUserID: Self.me) == .notOwnMessage)
    }

    @Test("A sender that could not be established is dropped")
    func sender_unknown_drops() {
        #expect(ReactionAlertTrigger.checkSender(nil, selfUserID: Self.me) == .senderUnknown)
    }
}

@Suite("Boost delta")
struct BoostDeltaTests {

    @Test("The delta is the rise over the actor's previous total")
    func delta_knownPrevious() {
        #expect(ReactionAlertTrigger.boostDeltaCents(newTotalCents: 800, previousCents: 300) == 500)
    }

    @Test("An unknown previous total shows the new total")
    func delta_unknownPrevious() {
        #expect(ReactionAlertTrigger.boostDeltaCents(newTotalCents: 500, previousCents: nil) == 500)
    }

    @Test("A previous total at or above the new one shows the new total")
    func delta_staleOrEqualPrevious() {
        #expect(ReactionAlertTrigger.boostDeltaCents(newTotalCents: 500, previousCents: 500) == 500)
        #expect(ReactionAlertTrigger.boostDeltaCents(newTotalCents: 500, previousCents: 900) == 500)
    }

    @Test("The tracker feeds each boost its predecessor, per actor and emoji")
    func tracker_perActorAndEmoji() {
        var tracker = ActorBoostTracker()
        let actor = UUID()
        func boost(_ emoji: String, by actor: UserID) -> DecodedReactionUpdate {
            DecodedReactionUpdate(messageID: MessageID(value: 1), emoji: emoji, actor: actor, added: true, boosted: true, count: 1, version: 1, reactedAt: nil)
        }
        #expect(tracker.recordBoost(boost("🔥", by: actor), newTotalCents: 500) == 500)
        #expect(tracker.recordBoost(boost("🔥", by: actor), newTotalCents: 800) == 300)
        #expect(tracker.recordBoost(boost("😂", by: actor), newTotalCents: 200) == 200)
        #expect(tracker.recordBoost(boost("🔥", by: UUID()), newTotalCents: 100) == 100)
    }

    @Test("A stale total does not lower the tracked total")
    func tracker_staleDoesNotRegress() {
        var tracker = ActorBoostTracker()
        let actor = UUID()
        let update = DecodedReactionUpdate(messageID: MessageID(value: 1), emoji: "🔥", actor: actor, added: true, boosted: true, count: 1, version: 1, reactedAt: nil)
        _ = tracker.recordBoost(update, newTotalCents: 800)
        _ = tracker.recordBoost(update, newTotalCents: 300)
        #expect(tracker.recordBoost(update, newTotalCents: 1000) == 200)
    }
}

@Suite("ReactionAlertPlacement")
struct ReactionAlertPlacementTests {

    private static let chat = ConversationID(data: Data(repeating: 1, count: 32))
    private static let elsewhere = ConversationID(data: Data(repeating: 2, count: 32))

    // Rows 1-2: the open chat raises no pill. `decide` takes no on-screen flag, so a message
    // scrolled off the screen gets the same answer as one in view.
    @Test("Open chat: bubble only, whether or not the message is on screen")
    func openChat() {
        #expect(ReactionAlertPlacement.decide(alertConversation: Self.chat, openConversation: Self.chat) == .bubbleOnly)
    }

    // Rows 3 and 8: a reaction or a boost in another chat takes the pill. The controller sends both
    // through `decide`; only the event's content differs.
    @Test("Another chat open: pill with the chat name")
    func otherChat() {
        #expect(ReactionAlertPlacement.decide(alertConversation: Self.chat, openConversation: Self.elsewhere) == .pill(.chatName))
    }

    // Row 4.
    @Test("No chat open: pill with the chat name")
    func noChat() {
        #expect(ReactionAlertPlacement.decide(alertConversation: Self.chat, openConversation: nil) == .pill(.chatName))
    }
}

@Suite("ReactionAlertQueue")
struct ReactionAlertQueueTests {

    private static let chat = ConversationID(data: Data(repeating: 1, count: 32))
    private static let other = ConversationID(data: Data(repeating: 2, count: 32))

    private static func event(
        conversation: ConversationID = chat,
        message: UInt64 = 1,
        emoji: String = "🔥",
        actor: UserID = UUID(),
        name: String = "Chloe",
        boost: UInt64? = nil
    ) -> ReactionAlertEvent {
        ReactionAlertEvent(
            conversationID: conversation, messageID: MessageID(value: message), emoji: emoji, actor: actor, actorName: name,
            isBoost: boost != nil, boostDeltaCents: boost ?? 0, snippet: "hello", topRow: "Moony"
        )
    }

    // Row 5: the pill on screen is the opened chat's, so the caller closes it and the queue moves on.
    @Test("Opening a chat leaves its showing pill to be closed, then advance promotes the next")
    func openedChatShowingPill() {
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event(conversation: Self.chat))
        queue.enqueue(Self.event(conversation: Self.other, message: 2))
        queue.removeWaiting(for: Self.chat)
        #expect(queue.current?.conversationID == Self.chat)
        #expect(queue.advance()?.conversationID == Self.other)
    }

    // Row 6.
    @Test("Opening a chat drops its waiting pills and keeps the others in order")
    func openedChatWaitingDropped() {
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event(conversation: Self.other, message: 9))
        queue.enqueue(Self.event(conversation: Self.chat, message: 1))
        queue.enqueue(Self.event(conversation: Self.other, message: 2))
        queue.enqueue(Self.event(conversation: Self.chat, message: 3, boost: 500))
        queue.removeWaiting(for: Self.chat)
        #expect(queue.current?.messageID == MessageID(value: 9))
        #expect(queue.waiting.map(\.messageID) == [MessageID(value: 2)])
        #expect(queue.advance()?.conversationID == Self.other)
        #expect(queue.advance() == nil)
    }

    @Test("The first event starts a pill")
    func firstStarts() {
        var queue = ReactionAlertQueue()
        #expect(queue.enqueue(Self.event()) == .started)
        #expect(queue.current?.title == "Chloe reacted to your message")
    }

    @Test("A boost reads as boosted, names the emoji and carries the delta")
    func boostPill() {
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event(boost: 500))
        #expect(queue.current?.title == "Chloe boosted their 🔥")
        #expect(queue.current?.boostCents == 500)
        #expect(queue.current?.hold == .milliseconds(3500))
    }

    @Test("A plain reaction holds 2.5 seconds and has no amount")
    func reactionHold() {
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event())
        #expect(queue.current?.hold == .milliseconds(2500))
        #expect(queue.current?.boostCents == nil)
    }

    @Test("Another actor on the same message merges into the several-actors pill")
    func sameMessageMerges() {
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event(emoji: "🔥", name: "Chloe"))
        #expect(queue.enqueue(Self.event(emoji: "😂", name: "Sam")) == .merged)
        queue.enqueue(Self.event(emoji: "❤️", name: "Ana"))
        #expect(queue.current?.title == "Chloe and 2 others reacted")
        #expect(queue.current?.emojis == ["🔥", "😂", "❤️"])
        #expect(queue.waiting.isEmpty)
    }

    @Test("Two actors read as one other")
    func singularOther() {
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event(name: "Chloe"))
        queue.enqueue(Self.event(emoji: "😂", name: "Sam"))
        #expect(queue.current?.title == "Chloe and 1 other reacted")
    }

    @Test("The same actor boosting again swaps in place and stays single-actor")
    func repeatBoostSwaps() {
        let actor = UUID()
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event(actor: actor, boost: 500))
        #expect(queue.enqueue(Self.event(actor: actor, boost: 300)) == .merged)
        #expect(queue.current?.events.count == 1)
        #expect(queue.current?.isStacked == false)
        #expect(queue.current?.boostCents == 300)
    }

    @Test("The stacked emoji list is capped at three, newest last")
    func emojiCap() {
        var queue = ReactionAlertQueue()
        for emoji in ["🔥", "😂", "❤️", "👍"] { queue.enqueue(Self.event(emoji: emoji)) }
        #expect(queue.current?.emojis == ["😂", "❤️", "👍"])
    }

    @Test("An event for another message waits for the current pill to close")
    func otherMessageQueues() {
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event(message: 1))
        #expect(queue.enqueue(Self.event(message: 2, name: "Sam")) == .queued)
        #expect(queue.current?.messageID == MessageID(value: 1))
        #expect(queue.waiting.count == 1)
    }

    @Test("Events for a waiting message merge into its waiting pill")
    func waitingMerges() {
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event(message: 1))
        queue.enqueue(Self.event(message: 2, name: "Sam"))
        queue.enqueue(Self.event(message: 2, emoji: "😂", name: "Ana"))
        #expect(queue.waiting.count == 1)
        #expect(queue.waiting[0].title == "Sam and 1 other reacted")
    }

    @Test("Advancing promotes the next pill, in order, then empties")
    func advance() {
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event(message: 1))
        queue.enqueue(Self.event(message: 2))
        queue.enqueue(Self.event(message: 3))
        #expect(queue.advance()?.messageID == MessageID(value: 2))
        #expect(queue.advance()?.messageID == MessageID(value: 3))
        #expect(queue.advance() == nil)
        #expect(queue.current == nil)
    }

    @Test("A new event after the queue empties starts afresh")
    func restartAfterEmpty() {
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event())
        queue.advance()
        #expect(queue.enqueue(Self.event(message: 9)) == .started)
    }

    @Test("Clearing drops the pill and everything waiting")
    func removeAll() {
        var queue = ReactionAlertQueue()
        queue.enqueue(Self.event(message: 1))
        queue.enqueue(Self.event(message: 2))
        queue.removeAll()
        #expect(queue.current == nil)
        #expect(queue.waiting.isEmpty)
    }
}

@Suite("IslandGeometry")
struct IslandGeometryTests {

    @Test("A notch phone has no island")
    func notch() {
        #expect(IslandGeometry.island(safeAreaTop: 47, screenWidth: 390) == nil)
        #expect(IslandGeometry.island(safeAreaTop: 50, screenWidth: 393) == nil)
    }

    @Test("A phone with no cutout inset has no island")
    func se() {
        #expect(IslandGeometry.island(safeAreaTop: 20, screenWidth: 375) == nil)
    }

    @Test("An island phone's island is centred and 126 by 37")
    func islandCentred() throws {
        let frame = try #require(IslandGeometry.island(safeAreaTop: 59, screenWidth: 393))
        #expect(frame.midX == 196.5)
        #expect(frame.size == CGSize(width: 126, height: 37))
    }

    @Test("An inset with no row of its own takes the nearest row below it")
    func unknownInset() {
        #expect(IslandGeometry.island(safeAreaTop: 70, screenWidth: 420) != nil)
    }
}
