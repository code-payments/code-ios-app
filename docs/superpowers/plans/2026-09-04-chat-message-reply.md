# Chat Message Reply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a person reply to any chat message — from the context menu or a swipe — see the quoted original above the composer and inside the sent bubble, and tap that quote to jump back to the original when it is in the local database.

**Architecture:** A reply is a decoration on a text message, not a new content kind. `ConversationMessage` gains `repliedTo: MessageID?`; the proto initializer unwraps `ReplyContent` so the inner `TextContent` still lands in `.text`, which means every existing `case .text` path (link detection, mapper, bubble, edit) is untouched. The pure mapper resolves that id into a display-ready `ChatQuote` (author, snippet, kind, target stable id) using a pre-resolved dictionary carried on `ConversationLoadCoordinator.Inputs`, so `map` stays pure and off-main. The UI is three additions: a strip above the composer's input row, a tinted panel inside the bubble above the body, and a pan recognizer on the transcript. Jump-to-original is one anchor move on `MessageLoader` plus a pending-target scroll on `ChatViewController` — no paging loop, no network call.

**Tech Stack:** Swift 6.1, SwiftUI + UIKit, ChatLayout + DifferenceKit, SQLite.swift, gRPC-Swift 2 via `FlipcashAPI` (`flipcash2-client-protocol` 0.2.0), Swift Testing.

---

## Scope

**In:** reply send, reply render (composer strip + in-bubble quote panel), reply entry from the context menu and from a swipe, tap-to-jump when the original is in the local database, `Reply`-only menus on cash and tip rows, persistence of `repliedToId`.

**Out:** proto work (`ReplyContent` already ships in `flipcash2-client-protocol` 0.2.0); fetching history that was never fetched in order to resolve a quote (renders as unavailable, tap does nothing); replying to a cash message with a cash message; group-chat author colors.

**No `SQLiteVersion` bump.** `Schema.swift:279` already declares `let repliedToId = Expression<UInt64?>("repliedToId")` and `Schema.swift:534` already adds the column; `Database+Conversations.swift:424` writes `nil` into it with the comment "The reply plan fills this in; the column exists now so the schema bumps once." Task 2 fills it in. **Do not add another column** (a cached quote snippet, an author name) — that would force a bump and rebuild every user's database. Everything the quote needs is derived at map time from a message already in the window or already in the table.

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatQuote.swift` | Display-ready quote value: author name, snippet, kind, target stable id. Pure data, no behavior. |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatQuotePanelView.swift` | The tinted quote panel drawn inside a bubble, above the body. Accent rule + two labels + a tap target. |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatSwipeToReply.swift` | Owns the reply pan recognizer and everything it tracks (target index path, translated cell, trigger latch). One named unit, per the hard rule. |
| `Flipcash/Core/Screens/Conversation/ComposerReplyStrip.swift` | The strip above the composer's input row: accent rule, author, snippet, dismiss. |
| `FlipcashTests/Chat/ChatQuoteMappingTests.swift` | Mapper quote resolution in all three states. |
| `FlipcashTests/Chat/ChatQuoteBubbleTests.swift` | Bubble geometry with and without a quote panel. |
| `FlipcashTests/Chat/ChatSwipeToReplyTests.swift` | The swipe's begin conditions and trigger threshold. |

### Modified files

| File | Change |
|---|---|
| `FlipcashCore/.../Models/Conversation/ConversationMessage.swift` | `repliedTo: MessageID?` on the struct, `init`, `replacingContent`, and the proto init's `.reply` unwrap. |
| `FlipcashCore/.../Models/Conversation/MessageCapability.swift` | `resolve` emits `.reply`; cash returns `[.reply]` instead of `[]`. |
| `FlipcashCore/.../Models/Chat/ChatMessage.swift` | `quote: ChatQuote?` on the struct and both inits. |
| `FlipcashCore/.../Clients/Flip API/Services/ChatMessagingService.swift` | `sendMessage` takes `repliedTo`, builds `ReplyContent` when set. |
| `FlipcashCore/.../Clients/Flip API/FlipClient+Chat.swift` | `sendMessage` signature. |
| `Flipcash/Core/Controllers/FlipClient+Protocols.swift` | `ConversationMessaging.sendMessage` signature. |
| `Flipcash/Core/Controllers/ConversationController.swift` | `repliedTo` through `send`/`retry`/`deliver`; new `persistedMessage(_:in:)`. |
| `Flipcash/Core/Controllers/Database/Database+Conversations.swift` | Write and read `repliedToId`. |
| `Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift` | `counterpartName` + `quotedMessage` parameters; builds `ChatQuote`. |
| `Flipcash/Core/Screens/Conversation/ConversationLoadCoordinator.swift` | `counterpartName` + `quotedMessages` on `Inputs`, pre-resolved in `currentInputs()`. |
| `Flipcash/Core/Screens/Conversation/MessageLoader.swift` | `reveal(_:)` — the one anchor move. |
| `Flipcash/Core/Screens/Conversation/ComposerModel.swift` | `Mode.replying(to:)` + `ReplyTarget`. |
| `Flipcash/Core/Screens/Conversation/ConversationBottomBar.swift` | Hosts the reply strip above the input row; submit sends with `repliedTo`. |
| `Flipcash/Core/Screens/Conversation/ChatScreenRepresentable.swift` | `.reply` focuses the composer; `onQuoteTap` wiring. |
| `Flipcash/Core/Screens/Conversation/ConversationScreen.swift` | `.reply` branch; `jumpToQuote`. |
| `FlipcashUI/.../Chat/ChatBubbleView.swift` | Quote panel above the label, conditional top constraint. |
| `FlipcashUI/.../Chat/LinkableBubbleView.swift` | Same panel, same constraints. |
| `FlipcashUI/.../Chat/ChatMessageCell.swift`, `ChatLinkMessageCell.swift` | `onQuoteTap` passthrough. |
| `FlipcashUI/.../Chat/ChatCashCardCell.swift` | Conforms to `BubbleCarrying` so the lift clips to the card. |
| `FlipcashUI/.../Chat/ChatViewController.swift` | `onQuoteTap`, `scrollToMessage(id:)`, pending scroll target, the reply pan, discriminating `shouldRecognizeSimultaneouslyWith`. |
| `FlipcashUI/.../Chat/ChatScreenViewController.swift` | `onQuoteTap` and `scrollToMessage(id:)` passthroughs. |
| `FlipcashUI/.../Theme/Image+Symbols.swift` | `replyArrow` symbol for the swipe affordance. |
| `FlipcashTests/TestSupport/MockConversations.swift` | `Sent` records `repliedTo`. |
| `FlipcashCore/Tests/.../MessageCapabilityTests.swift` | Rewrite the "cash offers nothing" test. |

---

## Task 1: `ConversationMessage` carries the replied-to id

Two things are wrong today. `ConversationMessage` has nowhere to put a replied-to id, and `init?(_ proto:)` returns `nil` for `case .reply` — so a reply sent from Android or the web **vanishes from the transcript entirely**. That is a live defect, and this task fixes it.

`Flipcash_Messaging_V1_ReplyContent` is `{ repliedMessageID: Flipcash_Messaging_V1_MessageId, hasRepliedMessageID: Bool, content: [Flipcash_Messaging_V1_Content] }`. The inner `content` is repeated, so the unwrap reads `replyContent.content.first?.type` and lands the inner text in `.text`.

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Models/Conversation/ConversationMessage.swift`
- Test: `FlipcashCore/Tests/FlipcashCoreTests/ConversationModelMappingTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `FlipcashCore/Tests/FlipcashCoreTests/ConversationModelMappingTests.swift`:

```swift
@Suite("Reply proto mapping")
struct ConversationMessageReplyMappingTests {

    private func replyProto(repliedTo: UInt64, text: String) -> Flipcash_Messaging_V1_Message {
        .with {
            $0.messageID = .with { $0.value = 42 }
            $0.content = [
                .with { content in
                    content.reply = .with { reply in
                        reply.repliedMessageID = .with { $0.value = repliedTo }
                        reply.content = [.with { inner in inner.text = .with { $0.text = text } }]
                    }
                }
            ]
        }
    }

    @Test("A reply proto maps to a text message carrying the replied-to id")
    func replyProto_unwrapsToText() throws {
        let message = try #require(ConversationMessage(replyProto(repliedTo: 7, text: "on my way")))
        #expect(message.content == .text("on my way"))
        #expect(message.repliedTo == MessageID(value: 7))
    }

    @Test("A plain text proto carries no replied-to id")
    func textProto_hasNoRepliedTo() throws {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 43 }
            $0.content = [.with { $0.text = .with { $0.text = "hi" } }]
        }
        let message = try #require(ConversationMessage(proto))
        #expect(message.repliedTo == nil)
    }

    @Test("A reply whose inner content is empty is dropped rather than rendered blank")
    func replyProto_withoutInnerContent_isDropped() {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 44 }
            $0.content = [
                .with { content in
                    content.reply = .with { reply in
                        reply.repliedMessageID = .with { $0.value = 7 }
                    }
                }
            ]
        }
        #expect(ConversationMessage(proto) == nil)
    }

    @Test("replacingContent preserves the replied-to id")
    func replacingContent_preservesRepliedTo() {
        let message = ConversationMessage(
            id: MessageID(value: 1),
            senderID: nil,
            content: .text("first"),
            date: Date(timeIntervalSince1970: 0),
            unreadSeq: 0,
            repliedTo: MessageID(value: 9)
        )
        let edited = message.replacingContent(.text("second"), lastEditedTs: Date(timeIntervalSince1970: 1))
        #expect(edited.repliedTo == MessageID(value: 9))
    }
}
```

Add `import FlipcashAPI` at the top of that file if it is not already there.

- [ ] **Step 2: Run the tests and watch them fail**

```bash
./Scripts/test.sh FlipcashCoreTests/ConversationMessageReplyMappingTests
```

Expected: compile failure — `ConversationMessage` has no `repliedTo` parameter or property.

- [ ] **Step 3: Add the property, the init parameter, and the unwrap**

In `ConversationMessage.swift`, add the stored property after `lastEditedTs`:

```swift
    /// The message this one replies to, or `nil` when it replies to nothing. A reply is a
    /// decoration on a text message rather than a content kind of its own: the wire nests the
    /// body inside `ReplyContent`, and the initializer below unwraps it so every `case .text`
    /// path — link detection, the transcript mapper, the bubble, edit — sees the shape it
    /// always saw.
    public let repliedTo: MessageID?
```

Add the parameter to `init`, after `lastEditedTs`:

```swift
        lastEditedTs: Date? = nil,
        repliedTo: MessageID? = nil,
        status: SendStatus = .sent,
```

and the assignment, after `self.lastEditedTs = lastEditedTs`:

```swift
        self.repliedTo = repliedTo
```

In `replacingContent(_:lastEditedTs:)`, add to the constructed value after `lastEditedTs: lastEditedTs`:

```swift
            repliedTo: repliedTo,
```

In `init?(_ proto:)`, replace the `.reply, .media, .system, .none` case and set `repliedTo` for the other cases. The switch becomes:

```swift
        let repliedTo: MessageID?
        switch proto.content.first?.type {
        case .text(let textContent):
            self.content = .text(textContent.text)
            self.cashAction = nil
            repliedTo = nil
        case .cash(let cashContent):
            guard let amount = try? ExchangedFiat(cashContent.amount) else {
                return nil
            }
            self.content = .cash(amount)
            // Unrecognized verbs fall back to `.sent`, per the proto contract.
            self.cashAction = cashContent.verb == .tipped ? .tipped : .sent
            repliedTo = nil
        case .deleted(let deletedContent):
            self.content = .deleted(
                Deletion(
                    deletedBy: deletedContent.hasDeletedBy ? try? UUID(data: deletedContent.deletedBy.value) : nil,
                    deletedAt: deletedContent.hasDeletedTs ? deletedContent.deletedTs.date : proto.ts.date
                )
            )
            self.cashAction = nil
            repliedTo = nil
        case .reply(let replyContent):
            // The wire nests the body one level down; unwrap it so the message is a text message
            // that happens to point at another, not a second shape every `case .text` must learn.
            // `content` is repeated on the wire but carries exactly one entry in practice — a
            // reply with nothing inside has no body to draw, so it is dropped like any other
            // content the client cannot represent.
            guard case .text(let textContent)? = replyContent.content.first?.type else {
                return nil
            }
            self.content = .text(textContent.text)
            self.cashAction = nil
            repliedTo = replyContent.hasRepliedMessageID ? MessageID(replyContent.repliedMessageID) : nil
        case .media, .system, .none:
            return nil
        }
```

and set the property alongside the others at the bottom of the initializer, after `self.lastEditedTs = ...`:

```swift
        self.repliedTo = repliedTo
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
./Scripts/test.sh FlipcashCoreTests/ConversationMessageReplyMappingTests FlipcashCoreTests/ConversationModelMappingTests FlipcashCoreTests/ConversationStoreTests
```

Expected: PASS. The existing suites are run too because `ConversationMessage`'s memberwise init gained a parameter.

- [ ] **Step 5: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models/Conversation/ConversationMessage.swift FlipcashCore/Tests/FlipcashCoreTests/ConversationModelMappingTests.swift
git commit -m "feat(chat): carry the replied-to id on ConversationMessage

A reply proto returned nil from the message initializer, so a reply sent from
another client never appeared in the transcript. Unwrap ReplyContent into the
text case it already is and keep the replied-to id beside it."
```

---

## Task 2: Persist `repliedToId`

The column already exists — `Schema.swift:279` declares it and `Schema.swift:534` adds it. `Database+Conversations.swift:424` writes `nil` into it today. **`SQLiteVersion` in `Info.plist` stays at 35**: no column is added, no type changes, and a row written before this task decodes as `repliedTo: nil`, which is exactly right for a message that was not a reply.

**Files:**
- Modify: `Flipcash/Core/Controllers/Database/Database+Conversations.swift:424` and `:507`
- Test: `FlipcashTests/Database/Database+ConversationsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `FlipcashTests/Database/Database+ConversationsTests.swift`, inside the existing conversation-messages suite:

```swift
    @Test("A reply round-trips its replied-to id through the database")
    func replyMessage_roundTripsRepliedTo() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let conversationID = ConversationID.test(1)
        let original = ConversationMessage(
            id: MessageID(value: 1), senderID: nil, content: .text("original"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0
        )
        let reply = ConversationMessage(
            id: MessageID(value: 2), senderID: nil, content: .text("replying"),
            date: Date(timeIntervalSince1970: 1), unreadSeq: 1,
            repliedTo: MessageID(value: 1)
        )
        try database.upsertConversationMessages([original, reply], conversationID: conversationID)

        let stored = try database.getConversationMessages(conversationID: conversationID)
        #expect(stored.first { $0.id == MessageID(value: 1) }?.repliedTo == nil)
        #expect(stored.first { $0.id == MessageID(value: 2) }?.repliedTo == MessageID(value: 1))
    }
```

- [ ] **Step 2: Run the test and watch it fail**

```bash
./Scripts/test.sh FlipcashTests/DatabaseConversationsTests/replyMessage_roundTripsRepliedTo
```

Expected: FAIL — the reply's `repliedTo` decodes as `nil`, because the write hard-codes `nil`.

- [ ] **Step 3: Write and read the column**

In `Database+Conversations.swift`, replace the write at `:423-424`:

```swift
                m.clientMessageID <- message.clientMessageID,
                m.repliedToId    <- message.repliedTo?.value,
```

(The comment above it goes with the `nil`.)

In the decoder's returned value, add after `lastEditedTs:`:

```swift
            lastEditedTs: row[m.lastEditedTs].map(Date.init(timeIntervalSinceReferenceDate:)),
            repliedTo: row[m.repliedToId].map(MessageID.init(value:)),
            clientMessageID: row[m.clientMessageID]
```

- [ ] **Step 4: Run the test and watch it pass**

```bash
./Scripts/test.sh FlipcashTests/DatabaseConversationsTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Controllers/Database/Database+Conversations.swift FlipcashTests/Database/Database+ConversationsTests.swift
git commit -m "feat(chat): persist a reply's replied-to message id

The column was added with the edit/delete schema bump and written as nil since.
Fill it in and read it back; no SQLiteVersion bump, because nothing about the
schema changes."
```

---

## Task 3: The menu offers Reply

Two changes to `MessageCapability.resolve`. Text messages gain `.reply` on both sides. Cash and tip messages return `[.reply]` instead of `[]` — today those rows offer no menu at all, because edit is impossible by contract and delete is deliberately excluded, which left the set empty.

`nextExpiry` needs no change: it skips any capability whose `policy.window(for:)` is `nil`, and `.reply` has no window.

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Models/Conversation/MessageCapability.swift`
- Test: `FlipcashCore/Tests/FlipcashCoreTests/MessageCapabilityTests.swift`

- [ ] **Step 1: Rewrite the cash test and add the reply tests**

In `MessageCapabilityTests.swift`, find and **delete** the test named
`"A cash message offers nothing in this scope — reply is the only capability it will ever have"`,
and add:

```swift
    @Test("A cash message offers Reply and nothing else")
    func cashMessage_offersReplyOnly() {
        let message = ConversationMessage(
            id: MessageID(value: 1), senderID: selfUserID, content: .cash(sampleFiat),
            cashAction: .sent, date: now, unreadSeq: 0, eventSequence: 1
        )
        let capabilities = MessageCapability.resolve(
            for: message, in: nil, as: selfUserID, policy: .init(editWindow: 900, deleteWindow: 900), now: now
        )
        #expect(capabilities == [.reply])
    }

    @Test("A received text message offers Copy and Reply")
    func receivedText_offersCopyAndReply() {
        let message = ConversationMessage(
            id: MessageID(value: 1), senderID: otherUserID, content: .text("hi"),
            date: now, unreadSeq: 0, eventSequence: 1
        )
        let capabilities = MessageCapability.resolve(
            for: message, in: nil, as: selfUserID, policy: .init(editWindow: 900, deleteWindow: 900), now: now
        )
        #expect(capabilities == [.copy, .reply])
    }

    @Test("An own text message inside both windows offers all four")
    func ownText_insideWindows_offersEverything() {
        let message = ConversationMessage(
            id: MessageID(value: 1), senderID: selfUserID, content: .text("hi"),
            date: now, unreadSeq: 0, eventSequence: 1
        )
        let capabilities = MessageCapability.resolve(
            for: message, in: nil, as: selfUserID, policy: .init(editWindow: 900, deleteWindow: 900), now: now
        )
        #expect(capabilities == [.copy, .reply, .edit, .delete])
    }

    @Test("An unconfirmed own message still offers nothing, so the menu does not grow rows mid-send")
    func unconfirmedOwnText_offersNothing() {
        let message = ConversationMessage(
            id: .unassigned, senderID: selfUserID, content: .text("hi"),
            date: now, unreadSeq: 0, eventSequence: 0, status: .sending, clientMessageID: UUID()
        )
        let capabilities = MessageCapability.resolve(
            for: message, in: nil, as: selfUserID, policy: .init(editWindow: 900, deleteWindow: 900), now: now
        )
        #expect(capabilities.isEmpty)
    }

    @Test("A tombstone still offers nothing")
    func tombstone_offersNothing() {
        let message = ConversationMessage(
            id: MessageID(value: 1), senderID: selfUserID,
            content: .deleted(.init(deletedBy: selfUserID, deletedAt: now)),
            date: now, unreadSeq: 0, eventSequence: 2
        )
        let capabilities = MessageCapability.resolve(
            for: message, in: nil, as: selfUserID, policy: .init(editWindow: 900, deleteWindow: 900), now: now
        )
        #expect(capabilities.isEmpty)
    }
```

Reuse the suite's existing `selfUserID` / `otherUserID` / `now` / `sampleFiat` fixtures and its `MessagePolicy` construction — if the suite builds a policy some other way, use that way rather than `.init(editWindow:deleteWindow:)`.

- [ ] **Step 2: Run the tests and watch them fail**

```bash
./Scripts/test.sh FlipcashCoreTests/MessageCapabilityTests
```

Expected: FAIL — cash resolves to `[]`, and text sets are missing `.reply`.

- [ ] **Step 3: Emit `.reply`**

In `MessageCapability.resolve`, replace the cash case:

```swift
        case .cash:
            // Reply is a cash message's only capability: there is no text to copy, the server
            // authored it so there is nothing to edit, and delete is deliberately withheld from
            // a payment record.
            return [.reply]
```

Replace the received-message early return:

```swift
        guard message.isFromSelf(selfUserID) else {
            return [.copy, .reply]
        }
```

Replace the base set for own messages:

```swift
        var capabilities: Set<MessageCapability> = [.copy, .reply]
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
./Scripts/test.sh FlipcashCoreTests/MessageCapabilityTests FlipcashTests/MessageCapabilityMenuTests
```

Expected: PASS. `MessageCapabilityMenuTests` may need its expected menus updated to include the Reply row — update the expectations, not the ordering (`ChatItem.orderedActions` already fixes `[.copy, .reply, .edit, .delete]`).

- [ ] **Step 5: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models/Conversation/MessageCapability.swift FlipcashCore/Tests/FlipcashCoreTests/MessageCapabilityTests.swift FlipcashTests/MessageCapabilityMenuTests.swift
git commit -m "feat(chat): offer Reply on text, cash, and tip rows

Cash and tip rows resolved to an empty capability set, so they carried no
context menu at all. Reply is the one thing they can offer, and it is now the
one thing they do."
```

---

## Task 4: `ChatQuote` and `ChatMessage.quote`

The display-ready quote. Everything the panel draws is resolved here at map time — the views stay dumb, and all three quote states are testable off a pure function.

`stableID` is `nil` for a quote that cannot be jumped to: an original outside the local database, or a tombstoned one (under `.hidden` the tombstone row is filtered out of the transcript, so there would be no row to land on).

**Files:**
- Create: `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatQuote.swift`
- Modify: `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessage.swift`
- Test: `FlipcashCore/Tests/FlipcashCoreTests/ChatQuoteTests.swift`

- [ ] **Step 1: Write the failing test**

Create `FlipcashCore/Tests/FlipcashCoreTests/ChatQuoteTests.swift`:

```swift
//
//  ChatQuoteTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("ChatQuote")
struct ChatQuoteTests {

    @Test("A short snippet is left alone")
    func shortSnippet_isUnchanged() {
        #expect(ChatQuote.snippet(forText: "on my way") == "on my way")
    }

    @Test("A long snippet is truncated with an ellipsis at the limit")
    func longSnippet_isTruncated() {
        let text = String(repeating: "a", count: ChatQuote.snippetLimit + 40)
        let snippet = ChatQuote.snippet(forText: text)
        #expect(snippet.count == ChatQuote.snippetLimit + 1)
        #expect(snippet.hasSuffix("…"))
    }

    @Test("Newlines collapse so the snippet stays one line")
    func newlines_collapse() {
        #expect(ChatQuote.snippet(forText: "line one\nline two") == "line one line two")
    }

    @Test("A quote with no target cannot be jumped to")
    func unresolvedQuote_hasNoTarget() {
        let quote = ChatQuote(stableID: nil, authorName: "", snippet: ChatQuote.unavailableSnippet, kind: .unavailable)
        #expect(quote.isJumpable == false)
    }

    @Test("A resolved quote can be jumped to")
    func resolvedQuote_hasTarget() {
        let quote = ChatQuote(stableID: "7", authorName: "You", snippet: "hi", kind: .text)
        #expect(quote.isJumpable)
    }

    @Test("A message carries no quote by default")
    func chatMessage_defaultsToNoQuote() {
        #expect(ChatMessage(id: "1", text: "hi", sender: .me).quote == nil)
    }
}
```

- [ ] **Step 2: Run the test and watch it fail**

```bash
./Scripts/test.sh FlipcashCoreTests/ChatQuoteTests
```

Expected: compile failure — no `ChatQuote`.

- [ ] **Step 3: Write `ChatQuote`**

Create `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatQuote.swift`:

```swift
//
//  ChatQuote.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The quoted original shown above a reply's body — display-ready, like everything else a chat row
/// draws. The transcript mapper resolves the replied-to id into one of these; the panel that draws
/// it knows nothing about the database or which messages happen to be loaded.
public struct ChatQuote: Hashable, Sendable, Codable {

    /// What the original was, which selects the panel's presentation.
    public enum Kind: Hashable, Sendable, Codable {
        case text
        /// A payment. The snippet is the formatted amount.
        case cash
        /// The original is not in the local database, or it has been deleted. The panel renders
        /// the placeholder copy and the row is not tappable.
        case unavailable
    }

    /// The transcript row to jump to, or `nil` when there is nothing to jump to.
    public let stableID: String?
    /// "You" for the viewer's own message, the counterpart's display name otherwise. Empty for an
    /// unavailable original, whose author is not known.
    public let authorName: String
    public let snippet: String
    public let kind: Kind

    public init(stableID: String?, authorName: String, snippet: String, kind: Kind) {
        self.stableID = stableID
        self.authorName = authorName
        self.snippet = snippet
        self.kind = kind
    }

    /// Whether tapping the panel goes anywhere.
    public var isJumpable: Bool { stableID != nil }

    /// Copy for an original the client cannot show.
    public static let unavailableSnippet = "Original message unavailable"

    /// Copy for an original that has since been deleted.
    public static let deletedSnippet = "This message was deleted"

    /// Longest snippet the panel renders. Past this the panel would wrap to a third line and the
    /// bubble would grow around a preview rather than the message.
    public static let snippetLimit = 120

    /// One line of preview text: newlines collapsed to spaces, truncated at ``snippetLimit``.
    public static func snippet(forText text: String) -> String {
        let flattened = text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flattened.count > snippetLimit else { return flattened }
        return flattened.prefix(snippetLimit) + "…"
    }
}
```

- [ ] **Step 4: Add `quote` to `ChatMessage`**

In `ChatMessage.swift`, add the stored property after `actions`:

```swift
    /// The original this row replies to, already resolved for display, or `nil` when the row is
    /// not a reply.
    public let quote: ChatQuote?
```

Add `quote: ChatQuote? = nil` as the last parameter of **both** initializers (after `actions:`), assign it in the full one:

```swift
        self.quote = quote
```

and forward it from the text convenience initializer:

```swift
            actions: actions,
            quote: quote
```

- [ ] **Step 5: Run the tests and watch them pass**

```bash
./Scripts/test.sh FlipcashCoreTests/ChatQuoteTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatQuote.swift FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessage.swift FlipcashCore/Tests/FlipcashCoreTests/ChatQuoteTests.swift
git commit -m "feat(chat): add the display-ready quote a reply row draws"
```

---

## Task 5: The mapper resolves the quote

`ChatItem.from` stays pure. It takes the counterpart's name and a lookup closure; the caller pre-resolves the messages. All three states — resolved, unavailable, deleted — are decided here, so all three are testable without a database.

**Files:**
- Modify: `Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift`
- Test: `FlipcashTests/Chat/ChatQuoteMappingTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

Create `FlipcashTests/Chat/ChatQuoteMappingTests.swift`:

```swift
//
//  ChatQuoteMappingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@Suite("Reply quote mapping")
struct ChatQuoteMappingTests {

    private let me = UUID()
    private let them = UUID()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func message(
        id: UInt64,
        from sender: UUID?,
        content: ConversationMessage.Content,
        repliedTo: UInt64? = nil,
        offset: TimeInterval = 0
    ) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: content,
            date: start.addingTimeInterval(offset),
            unreadSeq: id,
            eventSequence: id,
            repliedTo: repliedTo.map { MessageID(value: $0) }
        )
    }

    private func quotes(
        _ messages: [ConversationMessage],
        resolving pool: [ConversationMessage] = []
    ) -> [ChatQuote?] {
        let byID = Dictionary(uniqueKeysWithValues: (messages + pool).map { ($0.id, $0) })
        return ChatItem.from(
            messages,
            selfUserID: me,
            counterpartName: "Ada",
            quotedMessage: { byID[$0] }
        ).compactMap { item in
            if case .message(let message) = item { return message.quote } else { return nil }
        }
    }

    @Test("A reply to a message in the window quotes its author and text")
    func replyToWindowedMessage_resolves() throws {
        let original = message(id: 1, from: them, content: .text("dinner at 7?"))
        let reply = message(id: 2, from: me, content: .text("works"), repliedTo: 1, offset: 5)
        let quote = try #require(quotes([original, reply]).last ?? nil)
        #expect(quote.authorName == "Ada")
        #expect(quote.snippet == "dinner at 7?")
        #expect(quote.kind == .text)
        #expect(quote.stableID == original.stableID)
    }

    @Test("A reply to my own message names me")
    func replyToOwnMessage_namesMe() throws {
        let original = message(id: 1, from: me, content: .text("dinner at 7?"))
        let reply = message(id: 2, from: them, content: .text("works"), repliedTo: 1, offset: 5)
        let quote = try #require(quotes([original, reply]).last ?? nil)
        #expect(quote.authorName == "You")
    }

    @Test("A reply to a message outside the local database renders as unavailable and cannot be jumped to")
    func replyToUnknownMessage_isUnavailable() throws {
        let reply = message(id: 2, from: me, content: .text("works"), repliedTo: 99, offset: 5)
        let quote = try #require(quotes([reply]).last ?? nil)
        #expect(quote.kind == .unavailable)
        #expect(quote.snippet == ChatQuote.unavailableSnippet)
        #expect(quote.isJumpable == false)
    }

    @Test("A reply to a deleted message says so and cannot be jumped to")
    func replyToDeletedMessage_isUnavailable() throws {
        let original = message(
            id: 1, from: them,
            content: .deleted(ConversationMessage.Deletion(deletedBy: them, deletedAt: start))
        )
        let reply = message(id: 2, from: me, content: .text("works"), repliedTo: 1, offset: 5)
        // The tombstone itself is filtered out of the transcript under `.hidden`, so it is supplied
        // through the resolution pool rather than the window.
        let quote = try #require(quotes([reply], resolving: [original]).last ?? nil)
        #expect(quote.kind == .unavailable)
        #expect(quote.snippet == ChatQuote.deletedSnippet)
        #expect(quote.isJumpable == false)
    }

    private func fiat(_ amount: Decimal) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 0, mint: .usdf),
            nativeAmount: FiatAmount(value: amount, currency: .usd),
            currencyRate: Rate(fx: 1, currency: .usd)
        )
    }

    @Test("A reply to a payment quotes the formatted amount")
    func replyToCashMessage_quotesAmount() throws {
        let fiat = fiat(5)
        let original = message(id: 1, from: them, content: .cash(fiat))
        let reply = message(id: 2, from: me, content: .text("thanks!"), repliedTo: 1, offset: 5)
        let quote = try #require(quotes([original, reply]).last ?? nil)
        #expect(quote.kind == .cash)
        #expect(quote.snippet == fiat.nativeAmount.formatted())
    }

    @Test("A message that is not a reply carries no quote")
    func plainMessage_hasNoQuote() {
        let plain = message(id: 1, from: me, content: .text("hi"))
        #expect(quotes([plain]).last ?? nil == nil)
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

```bash
./Scripts/test.sh FlipcashTests/ChatQuoteMappingTests
```

Expected: compile failure — `ChatItem.from` has no `counterpartName` or `quotedMessage` parameter.

- [ ] **Step 3: Add the parameters and build the quote**

In `ChatItem+Conversation.swift`, add two parameters to `from(_:...)` after `capabilities:`:

```swift
        capabilities: (ConversationMessage) -> Set<MessageCapability> = { _ in [] },
        counterpartName: String = "",
        quotedMessage: (MessageID) -> ConversationMessage? = { _ in nil }
    ) -> [ChatItem] {
```

Inside the loop, after the `receipt` switch and before `items.append(.message(...))`:

```swift
            // Resolved here rather than in the view so all three states — found, never fetched,
            // deleted — are decided by one pure function and testable without a database.
            let quote = message.repliedTo.map { repliedTo in
                Self.quote(
                    resolving: quotedMessage(repliedTo),
                    selfUserID: selfUserID,
                    counterpartName: counterpartName
                )
            }
```

Add `quote: quote` as the last argument of the `ChatMessage(...)` construction:

```swift
                actions: orderedActions(capabilities(message)),
                quote: quote
            )))
```

Add the resolver beside `orderedActions`:

```swift
    /// The quoted original, for each of the three states it can be in. A message the local database
    /// has never seen and a tombstone both render as unavailable and both refuse the jump — the
    /// first because there is no row to land on, the second because `.hidden` filters the tombstone
    /// out of the transcript entirely.
    nonisolated private static func quote(
        resolving original: ConversationMessage?,
        selfUserID: UserID,
        counterpartName: String
    ) -> ChatQuote {
        guard let original else {
            return ChatQuote(
                stableID: nil,
                authorName: "",
                snippet: ChatQuote.unavailableSnippet,
                kind: .unavailable
            )
        }
        let authorName = original.isFromSelf(selfUserID) ? "You" : counterpartName
        switch original.content {
        case .text(let text):
            return ChatQuote(
                stableID: original.stableID,
                authorName: authorName,
                snippet: ChatQuote.snippet(forText: text),
                kind: .text
            )
        case .cash(let fiat):
            return ChatQuote(
                stableID: original.stableID,
                authorName: authorName,
                snippet: fiat.nativeAmount.formatted(),
                kind: .cash
            )
        case .deleted:
            return ChatQuote(
                stableID: nil,
                authorName: authorName,
                snippet: ChatQuote.deletedSnippet,
                kind: .unavailable
            )
        }
    }
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
./Scripts/test.sh FlipcashTests/ChatQuoteMappingTests FlipcashTests/ChatMessageMappingTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift FlipcashTests/Chat/ChatQuoteMappingTests.swift
git commit -m "feat(chat): resolve a reply's quoted original in the transcript mapper"
```

---

## Task 6: Feed the mapper its quotes

The coordinator pre-resolves every quoted message before mapping: from the window first, then from the local database. Both go on `Inputs`, so `map` stays pure and the equality short-circuit keeps working — a quote appearing because history was paged in changes `Inputs` and re-maps; an unrelated tick does not.

**Files:**
- Modify: `Flipcash/Core/Controllers/ConversationController.swift`
- Modify: `Flipcash/Core/Screens/Conversation/ConversationLoadCoordinator.swift`

- [ ] **Step 1: Add the persisted-message accessor**

In `ConversationController.swift`, beside `windowedMessages(for:startingAt:limit:)`:

```swift
    /// The locally-stored copy of one message, regardless of whether it is inside the rendered
    /// window. Reply quotes read through this: a reply can point at a message far above the
    /// window, and resolving it must not page the server. Observes `messageRevision`, so a quote
    /// that resolves once history lands re-maps like any other change.
    func persistedMessage(_ messageID: MessageID, in conversationID: ConversationID) -> ConversationMessage? {
        _ = messageRevision   // observe: re-read when a confirmed DB write lands
        return (try? database.message(id: messageID, conversationID: conversationID)) ?? nil
    }
```

- [ ] **Step 2: Carry the quotes on `Inputs`**

In `ConversationLoadCoordinator.swift`, add to `struct Inputs` after `conversation`:

```swift
        /// The counterpart's display name, for a quote whose original they wrote.
        var counterpartName: String
        /// Every message quoted by a reply in the window, pre-resolved so `map` stays pure. Keyed
        /// by raw id because `MessageID` is the natural key and the dictionary must be `Equatable`.
        var quotedMessages: [UInt64: ConversationMessage]
```

In `currentInputs()`, after the branding loop:

```swift
        let counterpartName = conversation?.counterpart(excluding: controller.selfUserID)?.displayName ?? ""
        // The window first — a reply to a nearby message resolves with no database read at all —
        // then the table, for a reply pointing above the window. Nothing pages the server: a quote
        // whose original was never fetched renders as unavailable, by design.
        var quotedMessages: [UInt64: ConversationMessage] = [:]
        for message in window {
            guard let repliedTo = message.repliedTo, quotedMessages[repliedTo.value] == nil else { continue }
            if let inWindow = window.first(where: { $0.id == repliedTo }) {
                quotedMessages[repliedTo.value] = inWindow
            } else if let persisted = controller.persistedMessage(repliedTo, in: conversationID) {
                quotedMessages[repliedTo.value] = persisted
            }
        }
```

and pass them, after `conversation: conversation,`:

```swift
            counterpartName: counterpartName,
            quotedMessages: quotedMessages,
```

In `map(_:)`, add after the `capabilities:` closure:

```swift
            counterpartName: inputs.counterpartName,
            quotedMessage: { inputs.quotedMessages[$0.value] }
```

Expose the resolved name so the composer strip names the author exactly as the bubble's panel
does — one source, not two:

```swift
    /// The counterpart's display name as the last mapping resolved it. The composer's reply strip
    /// reads this so the strip and the sent bubble's quote name the same person the same way.
    var counterpartName: String { lastInputs?.counterpartName ?? "" }
```

- [ ] **Step 3: Build**

Build the app scheme in Xcode (or via your usual build command) and confirm it compiles. There is no new behavior to unit-test here — the resolution logic under test lives in Task 5's pure mapper, and this task only supplies it.

- [ ] **Step 4: Run the surrounding suites**

```bash
./Scripts/test.sh FlipcashTests/ChatQuoteMappingTests FlipcashTests/MessageLoaderTests FlipcashTests/ConversationMutationTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Controllers/ConversationController.swift Flipcash/Core/Screens/Conversation/ConversationLoadCoordinator.swift
git commit -m "feat(chat): pre-resolve quoted originals for the transcript mapper

A reply can point above the rendered window, so resolution reads the window
first and the local table second. Neither pages the server."
```

---

## Task 7: `ComposerModel` learns to reply

A third mode beside `.new` and `.editing`. Two differences from editing, both deliberate:

- **The draft survives.** Starting a reply keeps whatever is already typed — WhatsApp does not throw it away, and unlike an edit there is no other text to swap in. So there is no stash.
- **`submission` behaves exactly like `.new`** — the trimmed draft, non-empty. There is no "unchanged" case to suppress.

`isEditing` and `editingStableID` stay false/nil in reply mode: they drive the cancel-edit morph and the edit spotlight, neither of which applies.

**Files:**
- Modify: `Flipcash/Core/Screens/Conversation/ComposerModel.swift`
- Test: `FlipcashTests/Chat/ComposerModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to the existing `ComposerModelTests` suite:

```swift
    private var replyTarget: ComposerModel.ReplyTarget {
        ComposerModel.ReplyTarget(
            messageID: MessageID(value: 7),
            stableID: "7",
            authorName: "Ada",
            snippet: "dinner at 7?"
        )
    }

    @Test("Starting a reply keeps what is already typed")
    func beginReplying_keepsDraft() {
        let composer = ComposerModel()
        composer.draft = "half a thought"
        composer.beginReplying(to: replyTarget)
        #expect(composer.draft == "half a thought")
        #expect(composer.replyTarget == replyTarget)
    }

    @Test("A reply submits its trimmed draft")
    func replying_submitsTrimmedDraft() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "  works  "
        #expect(composer.submission == "works")
        #expect(composer.canSubmit)
    }

    @Test("An empty reply cannot be submitted")
    func replyingWithEmptyDraft_cannotSubmit() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "   "
        #expect(composer.submission == nil)
        #expect(composer.canSubmit == false)
    }

    @Test("Dismissing the reply keeps the draft and clears the target")
    func endReplying_keepsDraft() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "works"
        composer.endReplying()
        #expect(composer.replyTarget == nil)
        #expect(composer.draft == "works")
    }

    @Test("A reply is not an edit")
    func replying_isNotEditing() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        #expect(composer.isEditing == false)
        #expect(composer.editingStableID == nil)
    }

    @Test("Starting an edit while replying drops the reply")
    func beginEditing_whileReplying_dropsReply() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.beginEditing(messageID: MessageID(value: 9), stableID: "9", currentText: "old")
        #expect(composer.replyTarget == nil)
        #expect(composer.isEditing)
        #expect(composer.draft == "old")
    }

    @Test("Clearing after a send drops the reply")
    func clear_dropsReply() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "works"
        composer.clear()
        #expect(composer.replyTarget == nil)
        #expect(composer.draft.isEmpty)
    }
```

- [ ] **Step 2: Run the tests and watch them fail**

```bash
./Scripts/test.sh FlipcashTests/ComposerModelTests
```

Expected: compile failure — no `beginReplying`.

- [ ] **Step 3: Add the mode**

In `ComposerModel.swift`, add the target type above `Mode`:

```swift
    /// What a reply is composed against — enough to render the strip and to address the send,
    /// so the composer never reaches back into the transcript for it.
    struct ReplyTarget: Equatable {
        let messageID: MessageID
        let stableID: String
        let authorName: String
        let snippet: String
    }
```

Add the case:

```swift
    enum Mode: Equatable {
        case new
        case editing(messageID: MessageID, stableID: String)
        case replying(to: ReplyTarget)
    }
```

Add the accessors beside `editingStableID`:

```swift
    /// The message this composer is replying to, or `nil` when it is not replying.
    var replyTarget: ReplyTarget? {
        switch mode {
        case .new, .editing:            nil
        case .replying(let target):     target
        }
    }
```

Extend `submission`'s switch with the reply case, which behaves like `.new`:

```swift
        case .new, .replying:
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
```

Extend `editingStableID` and `isEditing` — a reply is not an edit:

```swift
    var editingStableID: String? {
        switch mode {
        case .new, .replying:               nil
        case .editing(_, let stableID):     stableID
        }
    }

    var isEditing: Bool {
        switch mode {
        case .new, .replying:   false
        case .editing:          true
        }
    }
```

Add the transitions beside `beginEditing`/`endEditing`:

```swift
    /// Aims the composer at a message. Unlike an edit, the draft is left alone — a reply adds to
    /// what you were already typing rather than replacing it.
    func beginReplying(to target: ReplyTarget) {
        if isEditing { endEditing() }
        mode = .replying(to: target)
    }

    /// Dismisses the reply, keeping the draft — the strip's ⊗ takes back the target, not the text.
    func endReplying() {
        guard case .replying = mode else { return }
        mode = .new
    }
```

In `beginEditing`, the existing body already assigns `mode = .editing(...)`, which drops a reply target. Confirm it also stashes the draft as it does today — the `beginEditing_whileReplying_dropsReply` test covers the ordering.

In `clear()`, the existing `if mode != .new { mode = .new }` guard already drops a reply target; no change needed.

- [ ] **Step 4: Run the tests and watch them pass**

```bash
./Scripts/test.sh FlipcashTests/ComposerModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Screens/Conversation/ComposerModel.swift FlipcashTests/Chat/ComposerModelTests.swift
git commit -m "feat(chat): give the composer a reply mode

Unlike an edit, a reply keeps the draft: it adds to what you were typing
rather than replacing it, so there is nothing to stash."
```

---

## Task 8: The composer's reply strip

A quote strip above the input row, inside the bar's gradient background so it reads as one surface: full-bleed, a leading accent rule, the author on the first line, the snippet muted below, and a ⊗ at the trailing edge that clears back to `.new`.

The theme is monochrome — there is no green accent to borrow. The rule and the author line use the same white-opacity family the rest of the chat chrome uses.

**Files:**
- Create: `Flipcash/Core/Screens/Conversation/ComposerReplyStrip.swift`
- Modify: `Flipcash/Core/Screens/Conversation/ConversationBottomBar.swift`

- [ ] **Step 1: Write the strip**

Create `Flipcash/Core/Screens/Conversation/ComposerReplyStrip.swift`:

```swift
//
//  ComposerReplyStrip.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The quoted original above the composer while a reply is being written. Sits inside the bottom
/// bar's background rather than on top of it, so the bar reads as one surface that grew, and
/// dismissing it takes back the target without touching the draft.
struct ComposerReplyStrip: View {

    let target: ComposerModel.ReplyTarget
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // The leading rule is the quote's whole identity here; the panel has no fill of its own.
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.authorName)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                Text(target.snippet)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: SystemSymbol.close.rawValue)
                    .font(.default(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Replying to \(target.authorName): \(target.snippet)")
    }
}
```

- [ ] **Step 2: Mount it in the bar**

In `ConversationBottomBar.swift`, inside `ConversationBottomBar.body`, wrap the existing `content` so the strip sits above the input row and inside the gradient. Replace:

```swift
        return content.modifier(BarGradientBackground())
```

with:

```swift
        return VStack(spacing: 0) {
            if let target = composer.replyTarget {
                ComposerReplyStrip(target: target) {
                    withAnimation(barMorphSpring) { composer.endReplying() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            content
        }
        .animation(barMorphSpring, value: composer.replyTarget)
        .modifier(BarGradientBackground())
```

The strip is full-bleed by construction — the horizontal padding lives on `content`, not on the `VStack`.

- [ ] **Step 3: Report the taller bar**

The bar's height feeds the transcript's bottom inset through `setBarHeight(_:)`. Confirm the existing height measurement is a `GeometryReader`/`onGeometryChange` over the whole bar rather than a constant derived from `BarMetrics.contentHeight`: if it reads the rendered height, the strip is already accounted for and the transcript keeps its last message visible. If it is computed from `BarMetrics`, switch it to the measured height — a hard-coded height would leave the strip covering the newest row.

- [ ] **Step 4: Verify by hand**

Build and run. In a conversation:
- Long-press a message, choose Reply. The strip animates up, the keyboard raises, and the transcript scrolls so the last message stays above the taller bar.
- Type something, then tap ⊗. The strip animates away and **the text stays**.
- Type something, start a reply, then start an edit. The strip disappears, the draft becomes the edited message's text, and the cancel-edit button appears.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Screens/Conversation/ComposerReplyStrip.swift Flipcash/Core/Screens/Conversation/ConversationBottomBar.swift
git commit -m "feat(chat): show the quoted original above the composer"
```

---

## Task 9: Send the reply

`ReplyContent` wraps the text on the wire; the id rides beside it. Four signatures carry the replied-to id from the composer to the request, and the optimistic pending message carries it too so the quote is on the bubble the instant it appears rather than after the server confirms.

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Clients/Flip API/Services/ChatMessagingService.swift`
- Modify: `FlipcashCore/Sources/FlipcashCore/Clients/Flip API/FlipClient+Chat.swift`
- Modify: `Flipcash/Core/Controllers/FlipClient+Protocols.swift`
- Modify: `Flipcash/Core/Controllers/ConversationController.swift`
- Modify: `Flipcash/Core/Screens/Conversation/ConversationBottomBar.swift`
- Modify: `FlipcashTests/TestSupport/MockConversations.swift`
- Test: `FlipcashTests/Chat/ConversationReplySendTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

Create `FlipcashTests/Chat/ConversationReplySendTests.swift`:

```swift
//
//  ConversationReplySendTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Sending a reply")
struct ConversationReplySendTests {

    /// Mirrors `ConversationControllerTests.makeController` — the same four mocks and a temp DB.
    private func makeController(_ mock: MockConversations, selfUserID: UserID = UUID()) -> ConversationController {
        ConversationController(
            fetching: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: try! Database.makeTemp().database,
            owner: .generate()!, selfUserID: selfUserID,
            typingHeartbeatInterval: .seconds(3), incomingTypingExpiry: .seconds(10)
        )
    }

    @Test("A reply carries the replied-to id to the service")
    func send_carriesRepliedTo() async throws {
        let mock = MockConversations()
        mock.sendResult = ConversationMessage(
            id: MessageID(value: 8), senderID: nil, content: .text("works"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0, repliedTo: MessageID(value: 7)
        )
        let controller = makeController(mock)

        #expect(await controller.send("works", to: ConversationID.test(1), repliedTo: MessageID(value: 7)))

        let sent = try #require(mock.sent.last)
        #expect(sent.text == "works")
        #expect(sent.repliedTo == MessageID(value: 7))
    }

    @Test("A plain send carries no replied-to id")
    func send_withoutReply_carriesNothing() async throws {
        let mock = MockConversations()
        mock.sendResult = ConversationMessage(
            id: MessageID(value: 8), senderID: nil, content: .text("hi"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0
        )
        let controller = makeController(mock)

        #expect(await controller.send("hi", to: ConversationID.test(1)))

        let sent = try #require(mock.sent.last)
        #expect(sent.repliedTo == nil)
    }

    @Test("The optimistic row quotes the original before the server confirms")
    func failedReply_keepsRepliedTo() async throws {
        // A failed send leaves the optimistic row in the transcript, which is the same row the
        // successful path shows while it is in flight — so this reads the pending copy directly.
        let me = UUID()
        let mock = MockConversations()
        mock.sendError = ErrorSendMessage.transportFailure
        let controller = makeController(mock, selfUserID: me)

        _ = await controller.send("works", to: ConversationID.test(1), repliedTo: MessageID(value: 7))

        let pending = try #require(controller.messages(for: ConversationID.test(1)).first)
        #expect(pending.status == .failed)
        #expect(pending.repliedTo == MessageID(value: 7))
    }

    @Test("Retrying a failed reply keeps the replied-to id")
    func retry_keepsRepliedTo() async throws {
        let me = UUID()
        let mock = MockConversations()
        mock.sendError = ErrorSendMessage.transportFailure
        let controller = makeController(mock, selfUserID: me)

        _ = await controller.send("works", to: ConversationID.test(1), repliedTo: MessageID(value: 7))
        let failed = try #require(controller.messages(for: ConversationID.test(1)).first)
        let clientID = try #require(failed.clientMessageID)

        mock.sendError = nil
        mock.sendResult = ConversationMessage(
            id: MessageID(value: 9), senderID: me, content: .text("works"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0, repliedTo: MessageID(value: 7)
        )
        await controller.retry(clientMessageID: clientID, in: ConversationID.test(1))

        let sent = try #require(mock.sent.last)
        #expect(sent.repliedTo == MessageID(value: 7))
    }
}
```


- [ ] **Step 2: Run the tests and watch them fail**

```bash
./Scripts/test.sh FlipcashTests/ConversationReplySendTests
```

Expected: compile failure — `send` has no `repliedTo` parameter.

- [ ] **Step 3: Build the wire request**

In `ChatMessagingService.swift`, change the signature and the content construction:

```swift
    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, repliedTo: MessageID?, clientMessageID: UUID, completion: @Sendable @escaping (Result<ConversationMessage, ErrorSendMessage>) -> Void) {
        let request = Flipcash_Messaging_V1_SendMessageRequest.with {
            $0.chatID = conversationID.proto
            // A reply wraps the same text one level deeper on the wire. The domain model keeps it
            // flat — see `ConversationMessage.init?(_:)`, which unwraps it back.
            if let repliedTo {
                $0.content = [.with {
                    $0.reply = .with {
                        $0.repliedMessageID = repliedTo.proto
                        $0.content = [.with { $0.text = .with { $0.text = text } }]
                    }
                }]
            } else {
                $0.content = [.with { $0.text = .with { $0.text = text } }]
            }
            $0.clientMessageID = .with { $0.value = clientMessageID.data }
            $0.auth = owner.authFor(message: $0)
        }
```

- [ ] **Step 4: Thread the parameter through the other three signatures**

In `FlipClient+Chat.swift`, add `repliedTo: MessageID?` to the `sendMessage` wrapper and forward it to the service call.

In `FlipClient+Protocols.swift`, update the `ConversationMessaging` requirement to match:

```swift
    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, repliedTo: MessageID?, clientMessageID: UUID) async throws -> ConversationMessage
```

In `MockConversations.swift`, add the field to the record and the parameter to the method:

```swift
    struct Sent: Sendable {
        let conversationID: ConversationID
        let text: String
        let repliedTo: MessageID?
    }
```

and the method records it:

```swift
    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, repliedTo: MessageID?, clientMessageID: UUID) async throws -> ConversationMessage {
        lock.withLock {
            _sent.append(Sent(conversationID: conversationID, text: text, repliedTo: repliedTo))
            _sentClientIDs.append(clientMessageID)
        }
        if let error = sendError { throw error }
        return sendResult ?? ConversationMessage(
            id: MessageID(value: 1), senderID: nil, content: .text(text),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0, repliedTo: repliedTo
        )
    }
```

- [ ] **Step 5: Thread it through the controller**

In `ConversationController.swift`, `send` takes the id, puts it on the optimistic message, and passes it down:

```swift
    @discardableResult
    func send(_ text: String, to conversationID: ConversationID, repliedTo: MessageID? = nil) async -> Bool {
        let clientMessageID = UUID()
        let pending = ConversationMessage(
            id: .unassigned, senderID: selfUserID, content: .text(text),
            date: .now, unreadSeq: 0, status: .sending, clientMessageID: clientMessageID,
            repliedTo: repliedTo
        )
```

(keep the rest of the body, changing only the final call:)

```swift
        return await deliver(clientMessageID: clientMessageID, text: text, repliedTo: repliedTo, to: conversationID)
```

`retry` reads the id back off the pending message rather than being handed it, so a retry after a relaunch still quotes the right original:

```swift
        store.markPending(clientMessageID: clientMessageID, status: .sending, in: conversationID)
        _ = await deliver(clientMessageID: clientMessageID, text: text, repliedTo: pending.repliedTo, to: conversationID)
```

`deliver` takes it and forwards it:

```swift
    private func deliver(clientMessageID: UUID, text: String, repliedTo: MessageID?, to conversationID: ConversationID) async -> Bool {
```

with the messaging call becoming:

```swift
            let confirmed = try await messaging.sendMessage(
                owner: owner,
                conversationID: conversationID,
                text: text,
                repliedTo: repliedTo,
                clientMessageID: clientMessageID
            )
```

- [ ] **Step 6: Send from the composer**

In `ConversationBottomBar.swift`, extend `ConversationComposer.submit()`'s switch:

```swift
        switch composer.mode {
        case .new:
            guard let text = composer.submission else { return }
            composer.clear()
            isFocused = true
            Task { await conversationController.send(text, to: conversationID) }
        case .replying(let target):
            guard let text = composer.submission else { return }
            composer.clear()
            isFocused = true
            Task { await conversationController.send(text, to: conversationID, repliedTo: target.messageID) }
        case .editing(let messageID, _):
```

(the `.editing` body is unchanged.)

- [ ] **Step 7: Run the tests and watch them pass**

```bash
./Scripts/test.sh FlipcashTests/ConversationReplySendTests FlipcashTests/ConversationMutationTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Clients/Flip\ API/Services/ChatMessagingService.swift FlipcashCore/Sources/FlipcashCore/Clients/Flip\ API/FlipClient+Chat.swift Flipcash/Core/Controllers/FlipClient+Protocols.swift Flipcash/Core/Controllers/ConversationController.swift Flipcash/Core/Screens/Conversation/ConversationBottomBar.swift FlipcashTests/TestSupport/MockConversations.swift FlipcashTests/Chat/ConversationReplySendTests.swift
git commit -m "feat(chat): send a reply with the id of the message it answers

The optimistic row carries the id too, so the quote is on the bubble the
moment it appears rather than after the server confirms."
```

---

## Task 10: The quote panel inside the bubble

A tinted panel above the body, inside the same bubble background: its own leading rule, the author, the snippet. It is the jump target.

Two constraints that matter more than they look:

- **The cell class must not change.** `ChatItem+Differentiable.cellReuseIdentifier` picks the cell from the content kind and the link preview; a quote is not part of that decision. If a quote changed the identifier, DifferenceKit would delete and re-insert the row instead of updating it, and the send animation would flicker.
- **A hidden panel must occupy no height.** The panel is hidden *and* pinned to zero height when there is no quote, and the body's top constraint is swapped, not just deactivated — leaving both active makes the layout unsatisfiable.

**Files:**
- Create: `FlipcashUI/Sources/FlipcashUI/Chat/ChatQuotePanelView.swift`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatBubbleView.swift`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/LinkableBubbleView.swift`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatMessageCell.swift`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatLinkMessageCell.swift`
- Test: `FlipcashTests/Chat/ChatQuoteBubbleTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

Create `FlipcashTests/Chat/ChatQuoteBubbleTests.swift`:

```swift
//
//  ChatQuoteBubbleTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@Suite("Reply bubble quote panel")
@MainActor
struct ChatQuoteBubbleTests {

    private static let maxWidth: CGFloat = 250

    private let quote = ChatQuote(stableID: "7", authorName: "Ada", snippet: "dinner at 7?", kind: .text)

    private func laidOutCell(quote: ChatQuote?) -> ChatMessageCell {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        cell.configure(
            with: ChatMessage(id: "1", content: .text("works"), sender: .me, quote: quote),
            maxWidth: Self.maxWidth
        )
        let fitted = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 320, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: fitted.height)
        cell.layoutIfNeeded()
        return cell
    }

    @Test("A quote makes the bubble taller")
    func quote_growsTheBubble() {
        let plain = laidOutCell(quote: nil).bubbleView.frame.height
        let quoted = laidOutCell(quote: quote).bubbleView.frame.height
        #expect(quoted > plain)
    }

    @Test("A message with no quote reserves no height for the panel")
    func noQuote_reservesNothing() {
        let bubble = laidOutCell(quote: nil).bubbleView
        #expect(bubble.quotePanel.isHidden)
        #expect(bubble.quotePanel.frame.height == 0)
    }

    @Test("Reusing a bubble drops the previous quote")
    func reuse_dropsTheQuote() {
        let cell = laidOutCell(quote: quote)
        cell.configure(with: ChatMessage(id: "2", content: .text("hi"), sender: .me), maxWidth: Self.maxWidth)
        cell.layoutIfNeeded()
        #expect(cell.bubbleView.quotePanel.isHidden)
    }

    @Test("The panel reports the row it jumps to")
    func panel_reportsItsTarget() {
        var tapped: String?
        let cell = laidOutCell(quote: quote)
        cell.bubbleView.onQuoteTap = { tapped = $0 }
        cell.bubbleView.quotePanel.simulateTap()
        #expect(tapped == "7")
    }

    @Test("An unavailable quote is not tappable")
    func unavailableQuote_doesNotJump() {
        var tapped: String?
        let unavailable = ChatQuote(
            stableID: nil, authorName: "", snippet: ChatQuote.unavailableSnippet, kind: .unavailable
        )
        let cell = laidOutCell(quote: unavailable)
        cell.bubbleView.onQuoteTap = { tapped = $0 }
        cell.bubbleView.quotePanel.simulateTap()
        #expect(tapped == nil)
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

```bash
./Scripts/test.sh FlipcashTests/ChatQuoteBubbleTests
```

Expected: compile failure — no `quotePanel`.

- [ ] **Step 3: Write the panel**

Create `FlipcashUI/Sources/FlipcashUI/Chat/ChatQuotePanelView.swift`:

```swift
//
//  ChatQuotePanelView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// The quoted original drawn inside a reply's bubble, above the body: a leading rule, the author,
/// and one or two lines of the original. Tapping it asks to jump to that message — but only when
/// there is a row to jump to, which `ChatQuote.isJumpable` decides.
final class ChatQuotePanelView: UIView {

    /// Called with the target row's stable id when the panel is tapped. Silent for a quote that
    /// cannot be jumped to.
    var onTap: ((String) -> Void)?

    private var targetStableID: String?

    private let rule = UIView()
    private let authorLabel = UILabel()
    private let snippetLabel = UILabel()

    /// The panel's own inset from the bubble's edges — the body's leading inset, so the quote's
    /// rule and the text below it share one margin.
    static let horizontalInset: CGFloat = 12
    /// Gap between the panel and the body beneath it.
    static let bottomSpacing: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        backgroundColor = UIColor.white.withAlphaComponent(0.10)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        clipsToBounds = true

        rule.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        rule.layer.cornerRadius = 1
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)

        authorLabel.font = .default(size: 12, weight: .bold)
        authorLabel.textColor = .white
        authorLabel.numberOfLines = 1
        authorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(authorLabel)

        snippetLabel.font = .default(size: 12, weight: .medium)
        snippetLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        // One line in the bubble, per the spec: the panel is a citation, not a second message, and
        // a two-line panel over a one-line reply reads as the wrong thing being the point. The
        // composer's strip allows two, because there the quote *is* the subject.
        snippetLabel.numberOfLines = 1
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(snippetLabel)

        NSLayoutConstraint.activate([
            rule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rule.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            rule.widthAnchor.constraint(equalToConstant: 2),

            authorLabel.leadingAnchor.constraint(equalTo: rule.trailingAnchor, constant: 8),
            authorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            authorLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            snippetLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            snippetLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),
            snippetLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 1),
            snippetLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    func configure(with quote: ChatQuote) {
        targetStableID = quote.stableID
        // An unavailable original has no author to name, so the author line collapses rather than
        // rendering an empty run.
        authorLabel.text = quote.authorName
        authorLabel.isHidden = quote.authorName.isEmpty
        snippetLabel.text = quote.snippet
        isUserInteractionEnabled = quote.isJumpable
        accessibilityLabel = quote.authorName.isEmpty
            ? quote.snippet
            : "Replying to \(quote.authorName): \(quote.snippet)"
    }

    @objc private func handleTap() {
        guard let targetStableID else { return }
        onTap?(targetStableID)
    }

    /// Drives the tap path from tests, which cannot deliver a real touch to a detached view.
    func simulateTap() {
        guard isUserInteractionEnabled else { return }
        handleTap()
    }
}
#endif
```

The author line's `isHidden` collapses it because `authorLabel` has no explicit height and `snippetLabel` pins to its bottom — a hidden label with an empty string still lays out at zero height, which is what is wanted here.

- [ ] **Step 4: Mount it in `ChatBubbleView`**

In `ChatBubbleView.swift`, add the panel and the swap constraints:

```swift
    private(set) var quotePanel = ChatQuotePanelView()

    /// Forwarded from the panel: the stable id of the message to jump to.
    var onQuoteTap: ((String) -> Void)? {
        get { quotePanel.onTap }
        set { quotePanel.onTap = newValue }
    }

    /// Body pinned to the bubble's top, for a message with no quote.
    private var labelTopToBubble: NSLayoutConstraint!
    /// Body pinned below the quote panel, for a reply.
    private var labelTopToQuote: NSLayoutConstraint!
    /// Collapses the panel when there is no quote, so a hidden view consumes no height.
    private var quoteZeroHeight: NSLayoutConstraint!
```

In `setUp()`, after the label is added and before `NSLayoutConstraint.activate([...])`:

```swift
        quotePanel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(quotePanel)

        labelTopToBubble = label.topAnchor.constraint(equalTo: topAnchor, constant: 9)
        labelTopToQuote = label.topAnchor.constraint(
            equalTo: quotePanel.bottomAnchor,
            constant: ChatQuotePanelView.bottomSpacing
        )
        quoteZeroHeight = quotePanel.heightAnchor.constraint(equalToConstant: 0)
```

Replace the label's top constraint in the activation list with the panel's constraints plus the default top:

```swift
            quotePanel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            quotePanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ChatQuotePanelView.horizontalInset),
            quotePanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ChatQuotePanelView.horizontalInset),
            labelTopToBubble,
            quoteZeroHeight,
```

(the label's `bottomAnchor`, `leadingAnchor`, `trailingAnchor` and the `editedLabel` constraints are unchanged.)

In `configure(with:)`, before the `background.apply(...)` call:

```swift
        // Deactivate before activating: with both top constraints live the layout is
        // unsatisfiable, and UIKit resolves that by breaking one at random.
        if let quote = message.quote {
            quotePanel.isHidden = false
            quotePanel.configure(with: quote)
            quoteZeroHeight.isActive = false
            labelTopToBubble.isActive = false
            labelTopToQuote.isActive = true
        } else {
            quotePanel.isHidden = true
            labelTopToQuote.isActive = false
            labelTopToBubble.isActive = true
            quoteZeroHeight.isActive = true
        }
```

- [ ] **Step 5: Mount it in `LinkableBubbleView`**

Apply the same five edits to `LinkableBubbleView.swift`, with `textView` in place of `label`: the same `quotePanel`/`onQuoteTap`/three constraints, the same activation list swap (the text view's top constant is also `9`), and the same block in `configure(with:)`. Add the panel reset to `prepareForReuse()`:

```swift
    func prepareForReuse() {
        textView.resignFirstResponder()
        quotePanel.onTap = nil
    }
```

- [ ] **Step 6: Expose it on the cells**

`ChatMessageCell` and `ChatLinkMessageCell` already surface `bubbleView` for the alignment tests. Add the forwarding callback to both so the transcript can wire it in Task 13:

```swift
    var onQuoteTap: ((String) -> Void)? {
        get { bubbleView.onQuoteTap }
        set { bubbleView.onQuoteTap = newValue }
    }
```

- [ ] **Step 7: Run the tests and watch them pass**

```bash
./Scripts/test.sh FlipcashTests/ChatQuoteBubbleTests FlipcashTests/ChatBubbleViewTests
```

Expected: PASS. `ChatBubbleViewTests` passing unchanged is the point — a quote must not have disturbed the plain bubble's metrics.

- [ ] **Step 8: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatQuotePanelView.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatBubbleView.swift FlipcashUI/Sources/FlipcashUI/Chat/LinkableBubbleView.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatMessageCell.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatLinkMessageCell.swift FlipcashTests/Chat/ChatQuoteBubbleTests.swift
git commit -m "feat(chat): draw the quoted original inside a reply's bubble"
```

---

## Task 11: Verify the reply bubble's geometry

A quote panel changes a bubble's height and its intrinsic width. The row's horizontal placement is set by the stack view's alignment over a full-width message column, and the last regression there was a sideways shift on rows whose height changed. So the check is the one that caught it: lay out a real cell, and assert the bubble still hugs its sender's edge and still respects `maxWidth`, with a quote attached.

This task adds no production code. If an assertion fails, the fix belongs in Task 10's constraints — do not relax the assertion.

**Files:**
- Test: `FlipcashTests/Chat/ChatQuoteBubbleTests.swift` (extend)

- [ ] **Step 1: Write the geometry tests**

Add a second suite to `ChatQuoteBubbleTests.swift`:

```swift
@Suite("Reply bubble geometry")
@MainActor
struct ChatQuoteBubbleGeometryTests {

    private static let maxWidth: CGFloat = 250

    private let shortQuote = ChatQuote(stableID: "7", authorName: "Ada", snippet: "ok", kind: .text)
    private let longQuote = ChatQuote(
        stableID: "7",
        authorName: "Ada",
        snippet: String(repeating: "long enough to wrap ", count: 6),
        kind: .text
    )

    private func laidOutCell(sender: ChatMessage.Sender, quote: ChatQuote?, text: String = "works") -> (cell: ChatMessageCell, bubble: UIView) {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        cell.configure(
            with: ChatMessage(id: "1", content: .text(text), sender: sender, quote: quote),
            maxWidth: Self.maxWidth
        )
        let fitted = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 320, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: fitted.height)
        cell.layoutIfNeeded()
        return (cell, cell.contentView.subviews[0])
    }

    @Test("A quoted reply from me still hugs the trailing edge")
    func selfReply_hugsTrailing() {
        let (cell, bubble) = laidOutCell(sender: .me, quote: shortQuote)
        #expect(abs(bubble.frame.maxX - (cell.contentView.bounds.width - 12)) < 0.5)
        #expect(bubble.frame.minX > 12)
    }

    @Test("A quoted reply from them still hugs the leading edge")
    func otherReply_hugsLeading() {
        let (cell, bubble) = laidOutCell(sender: .other, quote: shortQuote)
        #expect(abs(bubble.frame.minX - 12) < 0.5)
        #expect(bubble.frame.maxX < cell.contentView.bounds.width - 12)
    }

    @Test("A quote wider than the body does not push the bubble past maxWidth")
    func longQuote_respectsMaxWidth() {
        let (_, bubble) = laidOutCell(sender: .me, quote: longQuote, text: "ok")
        #expect(bubble.frame.width <= Self.maxWidth + 0.5)
    }

    @Test("Adding a quote does not move the bubble sideways")
    func quote_doesNotShiftTheBubble() {
        let plain = laidOutCell(sender: .me, quote: nil)
        let quoted = laidOutCell(sender: .me, quote: shortQuote)
        // The height changes; the trailing edge must not.
        #expect(abs(plain.bubble.frame.maxX - quoted.bubble.frame.maxX) < 0.5)
    }

    @Test("A quote wider than the body widens the bubble to hold it")
    func longQuote_widensTheBubble() {
        let narrow = laidOutCell(sender: .me, quote: nil, text: "ok")
        let (_, wide) = laidOutCell(sender: .me, quote: longQuote, text: "ok")
        #expect(wide.frame.width > narrow.bubble.frame.width)
    }
}
```

- [ ] **Step 2: Run them**

```bash
./Scripts/test.sh FlipcashTests/ChatQuoteBubbleGeometryTests
```

Expected: PASS with Task 10's constraints as written. A failure on `quote_doesNotShiftTheBubble` or `longQuote_respectsMaxWidth` means the panel's leading/trailing constraints are fighting the bubble's width — fix the constraints in `ChatBubbleView`/`LinkableBubbleView`, not the test.

- [ ] **Step 3: Verify the animation by hand**

Build and run. Send a reply into a conversation with a screenful of history and watch the insert:
- The new row rises into place with the same spring as a plain send; the bubble does not slide horizontally as it settles.
- The rows above it do not jump when the taller row lands.
- Scroll up past the reply and back down — the row's height is stable across recycling.

- [ ] **Step 4: Commit**

```bash
git add FlipcashTests/Chat/ChatQuoteBubbleTests.swift
git commit -m "test(chat): pin the reply bubble's alignment and width"
```

---

## Task 12: The cash lift clips to the card

Cash and tip rows get a context menu for the first time in Task 3. `ChatCashCardCell` does not conform to `BubbleCarrying`, so the lift would raise the whole full-width cell instead of the card — visible as a full-width rectangle lifting out of the transcript.

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatCashCardCell.swift`

- [ ] **Step 1: Conform**

At the bottom of `ChatCashCardCell.swift`, inside the `#if canImport(UIKit)` block:

```swift
extension ChatCashCardCell: BubbleCarrying {
    /// The card, not the cell: the cell spans the full row, so lifting it would raise a
    /// full-width rectangle out of the transcript.
    var liftPreviewView: UIView { card }
    var liftPreviewMaskingPath: UIBezierPath? { card.maskingPath }
}
```

- [ ] **Step 2: Verify by hand**

Build and run. Long-press a cash bubble and a tip bubble:
- The lift raises the card alone, clipped to its rounded shape — matching a text bubble's lift.
- The menu shows one item, Reply.
- Choosing it opens the composer strip quoting the amount.

- [ ] **Step 3: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatCashCardCell.swift
git commit -m "fix(chat): clip the cash row's menu lift to the card

Cash rows gain a context menu with reply, and the cell spans the full row —
without this the lift raises a full-width rectangle."
```

---

## Task 13: Wire the menu and the quote tap

Two chains. The menu's Reply aims the composer and raises the keyboard, the way Edit already does. The quote tap travels cell → transcript → screen → representable → `ConversationScreen`.

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatScreenViewController.swift`
- Modify: `Flipcash/Core/Screens/Conversation/ChatScreenRepresentable.swift`
- Modify: `Flipcash/Core/Screens/Conversation/ConversationScreen.swift`

- [ ] **Step 1: Add the transcript's callback**

In `ChatViewController.swift`, beside `onMessageAction`:

```swift
    /// Called with a quoted message's stable id when its panel is tapped.
    public var onQuoteTap: ((String) -> Void)?
```

In `cellForItemAt`'s message branch, forward it on both text cells:

```swift
            case let cell as ChatLinkMessageCell:
                cell.configure(with: message, maxWidth: maxWidth)
                cell.onRetry = { [weak self] id in self?.onRetry?(id) }
                cell.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
                cell.onQuoteTap = { [weak self] id in self?.onQuoteTap?(id) }
            case let cell as ChatMessageCell:
                cell.configure(with: message, maxWidth: maxWidth)
                cell.onRetry = { [weak self] id in self?.onRetry?(id) }
                cell.onQuoteTap = { [weak self] id in self?.onQuoteTap?(id) }
```

- [ ] **Step 2: Pass it through the screen**

In `ChatScreenViewController.swift`, beside the other passthrough properties:

```swift
    public var onQuoteTap: ((String) -> Void)? {
        get { transcript.onQuoteTap }
        set { transcript.onQuoteTap = newValue }
    }
```

- [ ] **Step 3: Focus the composer on Reply**

In `ChatScreenRepresentable.swift`, extend `keyboardFollowing`'s switch — reply raises the keyboard like an edit, but takes no spotlight (the spotlight marks the row being rewritten; a reply's target is not being rewritten):

```swift
            switch action {
            case .edit:
                screen?.beginEditSpotlight(for: stableID)
                screen?.focusComposer()
            case .reply:
                screen?.focusComposer()
            case .delete:   screen?.dismissKeyboard()
            case .copy:     break
            }
```

- [ ] **Step 4: Add the representable's quote-tap parameter**

In `ChatScreenRepresentable`, add the stored closure beside the others:

```swift
    let onQuoteTap: (String) -> Void
```

and in **both** `makeUIViewController` and `updateUIViewController`, set it alongside the other callbacks:

```swift
        screen.onQuoteTap = { [weak screen] stableID in
            onQuoteTap(stableID)
            // The reveal may have to move the loader's anchor first, so the scroll records a
            // pending target when the row is not in the window yet.
            screen?.scrollToMessage(id: stableID)
        }
```

`scrollToMessage(id:)` is added in Task 14. **Do Task 14 before building this one** — this line does not compile without it. The two tasks are separated because they are separately reviewable, not because they land independently.

- [ ] **Step 5: Fill in the screen's reply branch**

In `ConversationScreen.swift`, replace the `.reply` stub in `handleMessageAction`:

```swift
        case .reply:
            composer.beginReplying(to: ComposerModel.ReplyTarget(
                messageID: message.id,
                stableID: stableID,
                authorName: message.isFromSelf(conversationController.selfUserID)
                    ? "You"
                    : (coordinator?.counterpartName ?? ""),
                snippet: Self.replySnippet(for: message)
            ))
```

with the snippet helper beside the other private helpers:

```swift
    /// The composer strip's preview of the message being answered — the same three-way split the
    /// transcript's quote panel uses, so the strip and the sent bubble read alike.
    private static func replySnippet(for message: ConversationMessage) -> String {
        switch message.content {
        case .text(let text):   ChatQuote.snippet(forText: text)
        case .cash(let fiat):   fiat.nativeAmount.formatted()
        case .deleted:          ChatQuote.deletedSnippet
        }
    }
```

A `.deleted` message cannot reach here: Task 3's `resolve` returns no capabilities for a tombstone, so its row has no menu. The branch exists to keep the switch exhaustive.

- [ ] **Step 6: Add the jump handler and pass it in**

Beside `handleMessageAction`:

```swift
    /// Brings the quoted original into the window when the local database has it. Returns without
    /// effect otherwise — history that was never fetched is out of scope, and the panel that
    /// points at it is already non-tappable.
    private func jumpToQuote(_ stableID: String) {
        guard let value = UInt64(stableID) else { return }
        _ = coordinator?.loader.reveal(MessageID(value: value))
    }
```

A pending row's stable id is a UUID string, so `UInt64(stableID)` fails and the jump is a no-op — correct, since an unconfirmed message is by definition at the bottom of the window already.

At the `ChatScreenRepresentable(...)` call site, add:

```swift
            onQuoteTap: jumpToQuote,
```

- [ ] **Step 7: Build and verify by hand**

Build and run:
- Long-press a message, choose Reply. The keyboard raises, the strip appears, and no row is spotlighted.
- Send it. The bubble shows the quote panel.
- Choose Reply on a cash bubble. The strip quotes the amount.

- [ ] **Step 8: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatScreenViewController.swift Flipcash/Core/Screens/Conversation/ChatScreenRepresentable.swift Flipcash/Core/Screens/Conversation/ConversationScreen.swift
git commit -m "feat(chat): start a reply from the message menu"
```

---

## Task 14: Jump to the quoted original

One anchor move, not a paging loop. `windowedMessages(for:startingAt:limit:)` with a `startID` reads every message from that id forward, so pointing the loader's anchor at the quoted id brings it into the window in a single step — no loop, no network call.

The remap lands asynchronously, so the scroll cannot happen inline. `ChatViewController` records the target and performs the scroll on the next update that contains it, applying that update without animation: animating a window that jumped hundreds of rows would draw a scroll through content the user never asked to see.

**Files:**
- Modify: `Flipcash/Core/Screens/Conversation/MessageLoader.swift`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatScreenViewController.swift`
- Test: `FlipcashTests/Chat/MessageLoaderRevealTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

Create `FlipcashTests/Chat/MessageLoaderRevealTests.swift`:

```swift
//
//  MessageLoaderRevealTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Revealing a quoted message")
struct MessageLoaderRevealTests {

    /// The same construction `MessageLoaderTests` uses — four mocks over a real temp database.
    private func makeController(_ database: Database) -> ConversationController {
        ConversationController(
            fetching: MockConversations(), messaging: MockConversations(), streaming: MockConversations(),
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: UUID(),
            typingHeartbeatInterval: .seconds(3), incomingTypingExpiry: .seconds(10)
        )
    }

    private func message(_ id: UInt64) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: nil, content: .text("m\(id)"),
            date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: id
        )
    }

    private func makeLoader(messageCount: Int) throws -> (loader: MessageLoader, url: URL) {
        let (database, url) = try Database.makeTemp()
        let id = ConversationID.test(1)
        try database.upsertConversationMessages((1...messageCount).map { message(UInt64($0)) }, conversationID: id)
        return (MessageLoader(conversationID: id, controller: makeController(database)), url)
    }

    @Test("A message already in the window needs no anchor move")
    func revealWindowed_keepsAnchor() throws {
        let (loader, url) = try makeLoader(messageCount: 10)
        defer { Database.removeTemp(at: url) }
        let target = try #require(loader.messages.first?.id)

        #expect(loader.reveal(target))
        #expect(loader.messages.contains { $0.id == target })
    }

    @Test("A message above the window is brought into it")
    func revealOlderMessage_movesAnchor() throws {
        let (loader, url) = try makeLoader(messageCount: 200)
        defer { Database.removeTemp(at: url) }
        // The initial window is the newest 60 (141...200), so 3 is well above it.
        let target = MessageID(value: 3)
        #expect(loader.messages.contains { $0.id == target } == false)

        #expect(loader.reveal(target))
        #expect(loader.messages.contains { $0.id == target })
    }

    @Test("A message the database has never seen cannot be revealed")
    func revealUnknownMessage_fails() throws {
        let (loader, url) = try makeLoader(messageCount: 10)
        defer { Database.removeTemp(at: url) }
        #expect(loader.reveal(MessageID(value: 9_999)) == false)
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

```bash
./Scripts/test.sh FlipcashTests/MessageLoaderRevealTests
```

Expected: compile failure — no `reveal`.

- [ ] **Step 3: Add `reveal`**

In `MessageLoader.swift`:

```swift
    /// Brings `messageID` into the rendered window, returning whether it is now there.
    ///
    /// One anchor move, not a paging loop: an anchored window reads every message from `startID`
    /// forward, so pointing the anchor at the target is enough. Nothing is fetched — a message the
    /// local database has never seen returns `false` and the caller leaves the transcript alone.
    @discardableResult
    func reveal(_ messageID: MessageID) -> Bool {
        if messages.contains(where: { $0.id == messageID }) { return true }
        guard controller.persistedMessage(messageID, in: conversationID) != nil else { return false }
        startID = messageID.value
        return true
    }
```

`startID` is currently `private`; `reveal` lives in the same type, so no access change is needed.

- [ ] **Step 4: Add the pending-target scroll**

In `ChatViewController.swift`, beside the other private state:

```swift
    /// A row asked for before it was in `items` — the loader's window has to move first. The next
    /// update carrying it performs the scroll.
    private var pendingScrollTargetID: String?
```

Add the public entry point beside `scrollToBottom(animated:)`:

```swift
    /// Scrolls the given row into view, or waits for the update that brings it in.
    public func scrollToMessage(id: String) {
        guard items.contains(where: { $0.differenceIdentifier.hasSuffix(":\(id)") }) else {
            pendingScrollTargetID = id
            return
        }
        scrollToRow(id: id, animated: true)
    }

    /// Centers a row that is already in `items`.
    private func scrollToRow(id: String, animated: Bool) {
        guard let index = items.firstIndex(where: { $0.differenceIdentifier.hasSuffix(":\(id)") }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        if animated {
            ChatMotion.scroll.animate {
                self.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
            }
        } else {
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        }
    }
```

Matching on the identifier's suffix is deliberate: `differenceIdentifier` is `"<cellClass>:<id>"`, and the caller knows only the id.

In `update(items:animated:)`, suppress the animation for the update that lands the target, and perform the scroll once it has:

```swift
    public func update(items newItems: [ChatItem], animated: Bool = true) {
        // A window that jumped hundreds of rows must not animate: it would draw a scroll through
        // content the user never asked to see.
        let animated = animated && pendingScrollTargetID == nil
```

and at the end of the method's completion — the same place `performInitialScrollIfNeeded()` is called on the non-animated path, and inside the staged-changeset `completion:` on the animated one:

```swift
        if let target = pendingScrollTargetID,
           self.items.contains(where: { $0.differenceIdentifier.hasSuffix(":\(target)") }) {
            self.pendingScrollTargetID = nil
            self.scrollToRow(id: target, animated: false)
        }
```

Add the same block to both paths — the target can land on either.

- [ ] **Step 5: Pass it through the screen**

In `ChatScreenViewController.swift`, beside `scrollToBottom`:

```swift
    public func scrollToMessage(id: String) { transcript.scrollToMessage(id: id) }
```

- [ ] **Step 6: Run the tests and watch them pass**

```bash
./Scripts/test.sh FlipcashTests/MessageLoaderRevealTests FlipcashTests/MessageLoaderTests
```

Expected: PASS.

- [ ] **Step 7: Verify by hand**

Build and run in a conversation with several hundred messages:
- Reply to a recent message, then tap the quote in the sent bubble. The transcript centers the original.
- Scroll to the bottom, then tap a quote whose original is far above the window. The window jumps to it without a visible scroll-through, and the original is centered.
- Scroll up to the very top and keep going. `loadOlder` still fetches past the moved anchor — the anchor moved, it was not pinned.
- Tap a quote panel that reads "Original message unavailable". Nothing happens, and nothing is fetched.

- [ ] **Step 8: Commit**

```bash
git add Flipcash/Core/Screens/Conversation/MessageLoader.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatScreenViewController.swift FlipcashTests/Chat/MessageLoaderRevealTests.swift
git commit -m "feat(chat): jump to a quoted message that is already stored

An anchored window reads from its start id forward, so revealing a message
above the window is one anchor move rather than a paging loop."
```

---

## Task 15: Swipe to reply — the riskiest task in this plan

**Read this section before writing any of it.**

A horizontal pan on the transcript has to coexist with two recognizers that already work:

1. **The collection view's own vertical scroll.** A pan that begins on any horizontal drift steals diagonal scrolls and the transcript feels sticky.
2. **The long-press lift.** `ChatViewController` currently returns unconditional `true` from `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` — written so the tap-to-dismiss recognizer never pre-empts a cell tap. Under that rule the new pan would run **during** a context-menu lift: the cell would slide sideways underneath its own floating preview.

So the fix is to make that method discriminating rather than to add a recognizer under it. The pan is the one recognizer that never runs simultaneously with anything.

The pan, the tracked index path, the translated cell, and the trigger latch are four pieces of state for one concern, so they live in their own type (`ChatSwipeToReply`) rather than as loose fields on the view controller.

**Files:**
- Create: `FlipcashUI/Sources/FlipcashUI/Chat/ChatSwipeToReply.swift`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift`
- Modify: `FlipcashUI/Sources/FlipcashUI/Theme/Image+Symbols.swift`
- Test: `FlipcashTests/Chat/ChatSwipeToReplyTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

The gesture's *decisions* are testable without a touch: whether it may begin, and whether a translation has crossed the trigger. Create `FlipcashTests/Chat/ChatSwipeToReplyTests.swift`:

```swift
//
//  ChatSwipeToReplyTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@Suite("Swipe to reply")
@MainActor
struct ChatSwipeToReplyTests {

    @Test("A mostly-horizontal drag may begin")
    func horizontalDrag_begins() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: -300, y: 40), isBlocked: false))
    }

    @Test("A mostly-vertical drag is left to the scroll view")
    func verticalDrag_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: -40, y: -300), isBlocked: false) == false)
    }

    @Test("A diagonal drag with more vertical than horizontal is left to the scroll view")
    func diagonalDrag_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: 120, y: -160), isBlocked: false) == false)
    }

    @Test("A drag towards the trailing edge is not a reply swipe")
    func trailingDrag_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: 300, y: 10), isBlocked: false) == false)
    }

    @Test("Nothing begins while the transcript is blocked")
    func blocked_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: -300, y: 40), isBlocked: true) == false)
    }

    @Test("Translation is clamped to the maximum")
    func translation_isClamped() {
        #expect(ChatSwipeToReply.offset(forTranslation: -500) == -ChatSwipeToReply.maxTranslation)
    }

    @Test("A drag towards the trailing edge does not move the row")
    func trailingTranslation_isIgnored() {
        #expect(ChatSwipeToReply.offset(forTranslation: 80) == 0)
    }

    @Test("Translation past the threshold resists")
    func translation_resistsPastThreshold() {
        let offset = ChatSwipeToReply.offset(forTranslation: -120)
        #expect(offset < -ChatSwipeToReply.triggerThreshold)
        #expect(offset > -120)
    }

    @Test("Crossing the threshold triggers the reply")
    func pastThreshold_triggers() {
        #expect(ChatSwipeToReply.triggers(offset: -ChatSwipeToReply.triggerThreshold - 1))
    }

    @Test("Releasing short of the threshold does not trigger")
    func shortOfThreshold_doesNotTrigger() {
        #expect(ChatSwipeToReply.triggers(offset: -ChatSwipeToReply.triggerThreshold + 1) == false)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
./Scripts/test.sh FlipcashTests/ChatSwipeToReplyTests
```

Expected: compile failure — no `ChatSwipeToReply`.

- [ ] **Step 3: Add the affordance symbol**

In `Image+Symbols.swift`, add to `SystemSymbol`:

```swift
    case replyArrow = "arrowshape.turn.up.left.fill"
```

- [ ] **Step 4: Write the gesture**

Create `FlipcashUI/Sources/FlipcashUI/Chat/ChatSwipeToReply.swift`:

```swift
//
//  ChatSwipeToReply.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// Drag a row towards the leading edge to reply to it.
///
/// Owns the whole gesture — the recognizer, the row being dragged, its offset, and whether the
/// trigger has already fired — because those four move together and splitting them across the
/// transcript's fields would make the coexistence rules impossible to follow. The transcript keeps
/// one `let` and answers two questions: which row is under a point, and whether it can be replied to.
@MainActor
final class ChatSwipeToReply: NSObject {

    /// Furthest a row travels. Past this the drag resists rather than stopping dead, so a hard
    /// swipe still feels connected to the finger.
    static let maxTranslation: CGFloat = 64
    /// Offset at which the reply fires on release.
    static let triggerThreshold: CGFloat = 48

    let recognizer = UIPanGestureRecognizer()

    /// The row under a point, if it can be replied to. The transcript answers this; the gesture
    /// does not know what a message is.
    var rowForSwipe: ((CGPoint) -> (cell: UICollectionViewCell, stableID: String)?)?
    /// Whether the transcript is busy — mid-update, or showing a context menu.
    var isBlocked: (() -> Bool)?
    /// Called once, when the drag crosses the threshold.
    var onTrigger: ((String) -> Void)?

    private var draggedCell: UICollectionViewCell?
    private var draggedStableID: String?
    private var hasTriggered = false
    private let affordance = UIImageView()
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    override init() {
        super.init()
        recognizer.addTarget(self, action: #selector(handlePan))
        recognizer.delegate = self
        recognizer.maximumNumberOfTouches = 1

        affordance.image = UIImage(systemName: SystemSymbol.replyArrow.rawValue)
        affordance.tintColor = UIColor.white.withAlphaComponent(0.55)
        affordance.contentMode = .scaleAspectFit
        affordance.alpha = 0
    }

    /// Whether a drag with this velocity is a reply swipe rather than a scroll.
    ///
    /// Horizontal dominance is the whole rule: a diagonal drag belongs to the scroll view, which
    /// would otherwise lose it to a recognizer that only ever moves sideways. Only leading-ward
    /// drags qualify — the trailing direction is left free for anything that wants it later.
    nonisolated static func shouldBegin(velocity: CGPoint, isBlocked: Bool) -> Bool {
        guard !isBlocked else { return false }
        guard velocity.x < 0 else { return false }
        return abs(velocity.x) > abs(velocity.y)
    }

    /// How far the row actually moves for a raw translation: clamped, with resistance past the max.
    nonisolated static func offset(forTranslation translation: CGFloat) -> CGFloat {
        guard translation < 0 else { return 0 }
        let distance = -translation
        guard distance > maxTranslation else { return translation }
        // Rubber band: everything past the max moves at a third speed, so the row keeps following
        // the finger without running off under the bubble beside it.
        return -(maxTranslation + (distance - maxTranslation) / 3)
    }

    /// Whether releasing at this offset fires the reply.
    nonisolated static func triggers(offset: CGFloat) -> Bool {
        offset < -triggerThreshold
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            begin(at: gesture.location(in: gesture.view))
        case .changed:
            let offset = Self.offset(forTranslation: gesture.translation(in: gesture.view).x)
            apply(offset: offset)
            if !hasTriggered, Self.triggers(offset: offset) {
                hasTriggered = true
                haptics.impactOccurred()
                if let draggedStableID { onTrigger?(draggedStableID) }
            }
        case .ended, .cancelled, .failed:
            settle()
        case .possible, .recognized:
            break
        @unknown default:
            settle()
        }
    }

    private func begin(at point: CGPoint) {
        guard let row = rowForSwipe?(point) else {
            recognizer.state = .cancelled
            return
        }
        draggedCell = row.cell
        draggedStableID = row.stableID
        hasTriggered = false
        haptics.prepare()

        affordance.alpha = 0
        affordance.frame = CGRect(x: row.cell.bounds.width - 34, y: (row.cell.bounds.height - 20) / 2, width: 20, height: 20)
        row.cell.contentView.addSubview(affordance)
    }

    private func apply(offset: CGFloat) {
        guard let draggedCell else { return }
        draggedCell.contentView.transform = CGAffineTransform(translationX: offset, y: 0)
        // The arrow fades in over the run-up to the trigger, so the gesture announces itself before
        // it fires rather than after.
        affordance.alpha = min(1, -offset / Self.triggerThreshold)
    }

    private func settle() {
        let cell = draggedCell
        draggedCell = nil
        draggedStableID = nil
        hasTriggered = false
        ChatMotion.swap.animate {
            cell?.contentView.transform = .identity
            self.affordance.alpha = 0
        } completion: { _ in
            self.affordance.removeFromSuperview()
        }
    }
}

extension ChatSwipeToReply: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        guard Self.shouldBegin(velocity: pan.velocity(in: pan.view), isBlocked: isBlocked?() ?? false) else {
            return false
        }
        return rowForSwipe?(pan.location(in: pan.view)) != nil
    }
}
#endif
```

- [ ] **Step 5: Mount it, and narrow the simultaneity rule**

In `ChatViewController.swift`, add the property beside the other private state:

```swift
    private let swipeToReply = ChatSwipeToReply()
```

In `viewDidLoad` (after the collection view is installed), wire it:

```swift
        swipeToReply.isBlocked = { [weak self] in
            guard let self else { return true }
            return self.isShowingContextMenu || self.isUpdating
        }
        swipeToReply.rowForSwipe = { [weak self] point in
            guard let self,
                  let indexPath = self.collectionView.indexPathForItem(at: point),
                  let cell = self.collectionView.cellForItem(at: indexPath),
                  case .message(let message) = self.items[indexPath.item],
                  message.actions.contains(.reply)
            else { return nil }
            return (cell, message.id)
        }
        swipeToReply.onTrigger = { [weak self] stableID in
            self?.onMessageAction?(stableID, .reply)
        }
        collectionView.addGestureRecognizer(swipeToReply.recognizer)
```

**Then narrow the simultaneity rule.** Replace the existing extension:

```swift
extension ChatViewController: UIGestureRecognizerDelegate {
    /// Lets the tap-to-dismiss recognizer fire alongside the collection view's own scroll and
    /// selection recognizers, so lowering the keyboard never pre-empts a cell tap.
    ///
    /// Swipe-to-reply is the exception: it translates a cell, so running it beside the scroll would
    /// drag a row sideways mid-scroll, and running it beside the long-press would slide the row out
    /// from under its own lift preview. It is exclusive in both directions.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === swipeToReply.recognizer || otherGestureRecognizer === swipeToReply.recognizer {
            return false
        }
        return true
    }
}
```

Reset any in-flight translation when the transcript reloads. In `update(items:animated:)`, on the non-animated path where `reloadData()` is called, add:

```swift
        swipeToReply.recognizer.isEnabled = false
        swipeToReply.recognizer.isEnabled = true
```

Toggling `isEnabled` cancels the gesture, which runs `settle()` and clears the cell's transform — a recycled cell must never inherit a translation.

- [ ] **Step 6: Run the tests and watch them pass**

```bash
./Scripts/test.sh FlipcashTests/ChatSwipeToReplyTests
```

Expected: PASS.

- [ ] **Step 7: Verification — coexistence with scrolling**

This is the half the unit tests cannot reach. Build, run, open a conversation with a few hundred messages, and check each:

- [ ] Flick vertically, hard, several times. Scrolling is as smooth as before; no row twitches sideways.
- [ ] Drag diagonally — down-and-left, up-and-left — at a shallow angle. The transcript scrolls; no row moves sideways.
- [ ] Drag slowly, almost straight left. The row follows the finger and the arrow fades in.
- [ ] Drag left past the maximum. The row resists rather than stopping dead, and never travels far enough to overlap the row beside it.
- [ ] Release short of the threshold. The row springs back with no reply started.
- [ ] Release past the threshold. One haptic, the strip appears, the row springs back.
- [ ] Drag right. Nothing moves.
- [ ] Start a leading drag and reverse direction mid-drag back past zero. The row does not travel to the trailing side.

- [ ] **Step 8: Verification — coexistence with the lift**

- [ ] Long-press a message to raise the menu, then drag sideways while the preview is lifted. The row underneath does not move.
- [ ] Long-press, dismiss the menu, then immediately swipe. The swipe works.
- [ ] Swipe past the threshold and, without lifting, keep the finger down. Only one haptic fires and only one strip appears — the latch holds.

- [ ] **Step 9: Verification — coexistence with updates and recycling**

- [ ] Swipe a row while a message arrives (send from another device, or let a poll land). The incoming row inserts and the swiped row still springs back to its own position, not to an offset one.
- [ ] Swipe a row, then scroll it off screen without releasing. Scroll back: no row is stuck at an offset.
- [ ] Swipe a cash bubble. It moves and starts a reply, like a text row.
- [ ] Swipe a deleted-message tombstone under a `.visible` policy. Nothing moves — it carries no `.reply` action.
- [ ] Swipe while a failed message is retrying. Nothing breaks.

- [ ] **Step 10: Verification — the keyboard**

- [ ] With the keyboard up and a draft typed, swipe a row. The strip appears, the draft survives, the keyboard stays up.
- [ ] With the composer already replying to A, swipe B. The strip retargets to B; the draft survives.

- [ ] **Step 11: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatSwipeToReply.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift FlipcashUI/Sources/FlipcashUI/Theme/Image+Symbols.swift FlipcashTests/Chat/ChatSwipeToReplyTests.swift
git commit -m "feat(chat): swipe a row towards the leading edge to reply

The pan is exclusive with every other recognizer. It translates a cell, so
running it beside the scroll would drag a row sideways mid-scroll, and
beside the long-press it would slide the row out from under its own lift."
```

---

## Final verification

- [ ] Run the chat suites:

```bash
./Scripts/test.sh FlipcashTests/ChatQuoteMappingTests FlipcashTests/ChatQuoteBubbleTests FlipcashTests/ChatQuoteBubbleGeometryTests FlipcashTests/ChatSwipeToReplyTests FlipcashTests/MessageLoaderRevealTests FlipcashTests/ComposerModelTests FlipcashTests/ConversationReplySendTests FlipcashTests/MessageCapabilityMenuTests
```

- [ ] Run the full suite from Xcode (`Product → Test`) — `Scripts/test.sh` deliberately does not run the whole plan.

- [ ] End-to-end, on device or simulator, against a real conversation:
  - Reply to a text message from the menu; the bubble quotes it; tap the quote and land on the original.
  - Reply by swipe; same result.
  - Reply to a cash bubble and to a tip bubble.
  - Reply to a message far above the window, scroll to the bottom, then tap the quote.
  - Receive a reply sent from Android and confirm it renders with its quote — this is the path that silently dropped the message before Task 1.
