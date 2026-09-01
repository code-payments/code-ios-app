# Chat Message Edit & Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a sender edit or delete their own chat message, with the transcript updating optimistically and reconciling against the server's `expected_event_sequence` answer.

**Architecture:** Three new units, per the spec. `MessageCapabilities` is a pure resolver in `FlipcashCore` that answers "what may this person do to this message" from the message, the conversation, the viewer, and a `MessagePolicy`. `ComposerModel` (app layer, `@Observable`) owns the draft and whether the composer is writing a new message or editing an existing one. `ConversationController+MessageMutations` holds `edit`/`delete`, each mirroring the existing `deliver` shape: optimistic overlay in `ConversationStore`, RPC, persist the server's answer, drop the overlay. The database stores server truth only; the optimistic edit/delete lives as a `MutationEntry` overlay composed inside `ConversationStore.displayedMessages(for:over:)`, exactly as `PendingEntry` already does for optimistic sends.

**Tech Stack:** Swift 6.1, SwiftUI + UIKit (ChatLayout / DifferenceKit transcript), SQLite.swift, gRPC-Swift 2 via `FlipcashAPI` (re-exported `flipcash2-client-protocol`), Swift Testing.

---

## Scope and deviations from the spec

This plan covers **edit and delete only**. Reply is a separate plan.

Deviations from `docs/superpowers/specs/2026-09-01-chat-message-actions-design.md`, each deliberate:

1. **One enum, not two.** The spec names both `MessageCapability` and `ChatMessageAction` with an identical case set. This plan defines a single `ChatMessageAction` used in both roles — as the capability set's element and as the menu row identity. Two enums that are always converted one-to-one is a mapping function with no reason to exist.
2. **`MessageCapabilities.resolve(...)` is a namespaced static**, not a module-scope free function. `FlipcashCore` has no module-scope functions; a `public enum MessageCapabilities` namespace matches how the module is organised.
3. **`.reply` is defined but never emitted.** The enum carries all four cases so the reply plan adds no enum churn, but `MessageCapabilities.resolve` does not return `.reply` in this scope. Shipping a Reply menu row that does nothing is worse than shipping no Reply row. The consequence is that cash and tip messages, whose only spec capability is `.reply`, offer no menu at all until the reply plan lands — which is today's behaviour, so nothing regresses.
4. **`resolve` takes `Conversation?`, not `Conversation`.** The transcript can paint before the `Conversation` record is in hand. A non-optional parameter would force the mapper to emit an empty capability set in that window, which would flicker the menu away. The parameter is unused today; it is the seam the future group-permissions model plugs into.
5. **`ComposerModel`, not `ComposerMode`.** It is an `@Observable` class that owns state, so it is named for the thing, not the enum inside it. Its `Mode` enum has `.new` and `.editing` only — `.replying` arrives with the reply plan.

Everything else follows the spec.

---

## File Structure

**New files**

| File | Responsibility |
|---|---|
| `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessageAction.swift` | The action/capability enum plus its display title and destructiveness. |
| `FlipcashCore/Sources/FlipcashCore/Models/Chat/MessagePolicy.swift` | `MessagePolicy` and `DeletedMessagePresentation` — the tunables capability resolution and tombstone rendering read. |
| `FlipcashCore/Sources/FlipcashCore/Models/Conversation/MessageCapabilities.swift` | Pure resolver: message + conversation + viewer + policy → `Set<ChatMessageAction>`. |
| `FlipcashCore/Sources/FlipcashCore/Models/Conversation/MutationEntry.swift` | The optimistic edit/delete overlay record. |
| `Flipcash/Core/Controllers/ConversationController+MessageMutations.swift` | `edit` / `delete` and their reconciliation. |
| `Flipcash/Core/Screens/Conversation/ComposerModel.swift` | Draft text plus composer mode (`.new` / `.editing`). |
| `FlipcashCore/Tests/FlipcashCoreTests/MessageCapabilitiesTests.swift` | The capability table. |
| `FlipcashCore/Tests/FlipcashCoreTests/ConversationStoreMutationTests.swift` | The overlay's apply/drop/stale behaviour. |
| `FlipcashTests/Chat/ChatMessageActionMenuTests.swift` | The context menu built from a message's actions. |
| `FlipcashTests/Chat/ComposerModelTests.swift` | Composer mode transitions and draft stashing. |
| `FlipcashTests/ConversationMutationTests.swift` | Controller-level edit/delete against `MockConversations`. |

**Modified files**

| File | Change |
|---|---|
| `FlipcashCore/.../Models/Conversation/ConversationMessage.swift` | `Deletion` payload on `.deleted`, `lastEditedTs`, `replacingContent`. |
| `FlipcashCore/.../Models/Conversation/ConversationStore.swift` | Mutation overlay applied in `displayedMessages`. |
| `FlipcashCore/.../Models/Chat/ChatMessage.swift` | `.deleted(String)` content case, `isEdited`, `actions`. |
| `FlipcashCore/.../Clients/Flip API/Services/ChatMessagingService.swift` | `editMessage` / `deleteMessage` RPC wrappers, `MessageMutation`, error enums. |
| `FlipcashCore/.../Clients/Flip API/FlipClient+Chat.swift` | Async continuations for both. |
| `FlipcashUI/.../Chat/ChatItem+Differentiable.swift` | Cell class for `.deleted`. |
| `FlipcashUI/.../Chat/ChatBubbleView.swift` | Tombstone text and the "Edited" marker. |
| `FlipcashUI/.../Chat/LinkableBubbleView.swift` | `.deleted` case in its content switch. |
| `FlipcashUI/.../Chat/ChatViewController.swift` | Menu built from `message.actions`; `onMessageAction`. |
| `FlipcashUI/.../Chat/ChatScreenViewController.swift` | `onMessageAction` pass-through. |
| `FlipcashUI/.../Theme/Image+Symbols.swift` | `pencil`, `trash`. |
| `Flipcash/Core/Controllers/Database/Schema.swift` | Four new message columns. |
| `Flipcash/Core/Controllers/Database/Database+Conversations.swift` | Write/read the new columns; single-message accessor. |
| `Flipcash/Core/Controllers/ConversationController.swift` | New write-operation names; `mutationAlert`. |
| `Flipcash/Core/Controllers/FlipClient+Protocols.swift` | `ConversationMessaging` gains both methods. |
| `Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift` | Capabilities, tombstone presentation, receipt anchor. |
| `Flipcash/Core/Screens/Conversation/ConversationLoadCoordinator.swift` | Policy and conversation enter `Inputs`. |
| `Flipcash/Core/Screens/Conversation/ConversationBottomBar.swift` | Composer split; edit banner; submit routing. |
| `Flipcash/Core/Screens/Conversation/ChatScreenRepresentable.swift` | Composer and `onMessageAction` plumbing. |
| `Flipcash/Core/Screens/Conversation/ConversationScreen.swift` | Menu action handling, delete confirmation, alert presentation. |
| `Flipcash/Supporting Files/Info.plist` | `SQLiteVersion` 34 → 35. |
| `FlipcashTests/TestSupport/MockConversations.swift` | Records edit/delete calls. |

**Tests updated in place** (existing call sites of `.deleted`): `FlipcashCore/Tests/FlipcashCoreTests/ConversationStreamEventDecodeTests.swift`, `FlipcashTests/ChatPreviewMappingTests.swift`, `FlipcashTests/Database/Database+ConversationsTests.swift`, `FlipcashTests/Chat/ChatMessageMappingTests.swift`.

---

## Task 1: `ConversationMessage` carries deletion detail and an edit stamp

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Models/Conversation/ConversationMessage.swift`
- Modify: `FlipcashCore/Tests/FlipcashCoreTests/ConversationStreamEventDecodeTests.swift:228`
- Test: `FlipcashCore/Tests/FlipcashCoreTests/ConversationModelMappingTests.swift`

`Content.deleted` becomes `.deleted(Deletion)` so the transcript can say "You deleted this message" versus "This message was deleted". The proto initialiser also stops dropping `lastEditedTs`.

- [ ] **Step 1: Write the failing test**

Append to `FlipcashCore/Tests/FlipcashCoreTests/ConversationModelMappingTests.swift`:

```swift
@Suite("ConversationMessage deletion and edit metadata")
struct ConversationMessageMetadataTests {

    private let deleter = UUID()

    @Test("A tombstone carries who deleted it and when")
    func tombstoneCarriesDeletionDetail() throws {
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 9 }
            $0.eventSequence = 3
            $0.content = [.with {
                $0.deleted = .with {
                    $0.deletedTs = .init(date: deletedAt)
                    $0.deletedBy = .with { $0.value = deleter.data }
                }
            }]
        }

        let message = try #require(ConversationMessage(proto))
        guard case .deleted(let deletion) = message.content else {
            Issue.record("expected a deleted message")
            return
        }
        #expect(deletion.deletedBy == deleter)
        #expect(deletion.deletedAt == deletedAt)
    }

    @Test("An edited message keeps the server's edit timestamp")
    func editedMessageKeepsTimestamp() throws {
        let editedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 10 }
            $0.eventSequence = 4
            $0.lastEditedTs = .init(date: editedAt)
            $0.content = [.with { $0.text = .with { $0.text = "fixed" } }]
        }

        let message = try #require(ConversationMessage(proto))
        #expect(message.lastEditedTs == editedAt)
        #expect(message.content == .text("fixed"))
    }

    @Test("A never-edited message has no edit timestamp")
    func unEditedMessageHasNoTimestamp() throws {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 11 }
            $0.eventSequence = 1
            $0.content = [.with { $0.text = .with { $0.text = "hi" } }]
        }

        let message = try #require(ConversationMessage(proto))
        #expect(message.lastEditedTs == nil)
    }

    @Test("replacingContent preserves identity and ordering")
    func replacingContentPreservesIdentity() {
        let original = ConversationMessage(
            id: MessageID(value: 12), senderID: deleter, content: .text("before"),
            date: Date(timeIntervalSince1970: 100), unreadSeq: 4, eventSequence: 7
        )
        let edited = original.replacingContent(.text("after"), lastEditedTs: Date(timeIntervalSince1970: 200))

        #expect(edited.content == .text("after"))
        #expect(edited.id == original.id)
        #expect(edited.eventSequence == 7)
        #expect(edited.unreadSeq == 4)
        #expect(edited.date == original.date)
        #expect(edited.lastEditedTs == Date(timeIntervalSince1970: 200))
    }
}
```

Make sure the file's imports include `import FlipcashAPI` and `import Foundation` — add whichever is missing at the top.

- [ ] **Step 2: Run the test to verify it fails**

```bash
./Scripts/test.sh FlipcashCoreTests/ConversationMessageMetadataTests
```

Expected: compile failure — `value of type 'ConversationMessage' has no member 'lastEditedTs'`, and `'deleted' cannot be used as a pattern with an associated value`.

- [ ] **Step 3: Add the deletion payload, the edit stamp, and `replacingContent`**

In `ConversationMessage.swift`, replace the `Content` enum and add the stored properties. The struct becomes:

```swift
public struct ConversationMessage: Identifiable, Hashable, Sendable {

    /// Who removed a message and when — the tombstone's payload. `deletedBy` is `nil` when the
    /// server does not attribute the deletion (a moderation removal, for instance).
    public struct Deletion: Hashable, Sendable {
        public let deletedBy: UserID?
        public let deletedAt: Date

        public init(deletedBy: UserID?, deletedAt: Date) {
            self.deletedBy = deletedBy
            self.deletedAt = deletedAt
        }
    }

    public enum Content: Hashable, Sendable {
        case text(String)
        case cash(ExchangedFiat)
        case deleted(Deletion)
    }

    public let id: MessageID
    public let senderID: UserID?
    public let content: Content
    public let cashAction: CashAction?
    public let date: Date
    public let unreadSeq: UInt64
    public let eventSequence: UInt64
    /// When the sender last edited this message, or `nil` if it has never been edited.
    public let lastEditedTs: Date?
    public var status: SendStatus
    public var clientMessageID: UUID?

    public init(
        id: MessageID,
        senderID: UserID?,
        content: Content,
        cashAction: CashAction? = nil,
        date: Date,
        unreadSeq: UInt64,
        eventSequence: UInt64 = 0,
        lastEditedTs: Date? = nil,
        status: SendStatus = .sent,
        clientMessageID: UUID? = nil
    ) {
        self.id = id
        self.senderID = senderID
        self.content = content
        self.cashAction = cashAction
        self.date = date
        self.unreadSeq = unreadSeq
        self.eventSequence = eventSequence
        self.lastEditedTs = lastEditedTs
        self.status = status
        self.clientMessageID = clientMessageID
    }
}
```

Add to the `extension ConversationMessage` that holds `stableID`:

```swift
    /// Whether this message has been replaced by a tombstone.
    public var isDeleted: Bool {
        if case .deleted = content { true } else { false }
    }

    /// A copy carrying different content. Identity, ordering, and delivery status are preserved —
    /// this exists for the optimistic mutation overlay, which changes what a message says and
    /// nothing else about where it sits.
    public func replacingContent(_ content: Content, lastEditedTs: Date?) -> ConversationMessage {
        ConversationMessage(
            id: id,
            senderID: senderID,
            content: content,
            cashAction: cashAction,
            date: date,
            unreadSeq: unreadSeq,
            eventSequence: eventSequence,
            lastEditedTs: lastEditedTs,
            status: status,
            clientMessageID: clientMessageID
        )
    }
```

In the proto initialiser, replace the `.deleted` branch and add the edit stamp:

```swift
            case .deleted(let deletedContent):
                self.content = .deleted(
                    Deletion(
                        deletedBy: deletedContent.hasDeletedBy ? try? UUID(data: deletedContent.deletedBy.value) : nil,
                        deletedAt: deletedContent.hasDeletedTs ? deletedContent.deletedTs.date : proto.ts.date
                    )
                )
                self.cashAction = nil
```

and, alongside `self.eventSequence = proto.eventSequence`:

```swift
        self.lastEditedTs = proto.hasLastEditedTs ? proto.lastEditedTs.date : nil
```

- [ ] **Step 4: Fix the one broken core test**

`FlipcashCore/Tests/FlipcashCoreTests/ConversationStreamEventDecodeTests.swift:228` compares against the payload-free case. Replace that line:

```swift
        #expect(tombstone.isDeleted)
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashCoreTests/ConversationMessageMetadataTests FlipcashCoreTests/ConversationStreamEventDecodeTests
```

Expected: PASS for both suites.

- [ ] **Step 6: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models/Conversation/ConversationMessage.swift FlipcashCore/Tests/FlipcashCoreTests/ConversationModelMappingTests.swift FlipcashCore/Tests/FlipcashCoreTests/ConversationStreamEventDecodeTests.swift
git commit -m "feat(chat): carry deletion detail and edit stamps on conversation messages"
```

---

## Task 2: Persist the deletion detail and edit stamp

**Files:**
- Modify: `Flipcash/Core/Controllers/Database/Schema.swift:252-276` and its creation block at `:507-527`
- Modify: `Flipcash/Core/Controllers/Database/Database+Conversations.swift`
- Modify: `Flipcash/Supporting Files/Info.plist:26`
- Test: `FlipcashTests/Database/Database+ConversationsTests.swift`

There are no migrations here — the database is rebuilt from the server, gated on `SQLiteVersion`. Bumping it is mandatory, not optional.

- [ ] **Step 1: Write the failing test**

Append to `FlipcashTests/Database/Database+ConversationsTests.swift`, inside the existing suite:

```swift
    @Test("A tombstone round-trips its deleter and timestamp")
    func tombstoneRoundTrips() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let conversationID = ConversationID(data: Data(repeating: 7, count: 32))
        let deleter = UUID()
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let message = ConversationMessage(
            id: MessageID(value: 4), senderID: deleter,
            content: .deleted(.init(deletedBy: deleter, deletedAt: deletedAt)),
            date: Date(timeIntervalSince1970: 1_699_999_000), unreadSeq: 1, eventSequence: 5
        )

        try database.upsertConversationMessages([message], conversationID: conversationID)

        let stored = try #require(try database.message(id: MessageID(value: 4), conversationID: conversationID))
        guard case .deleted(let deletion) = stored.content else {
            Issue.record("expected a deleted message")
            return
        }
        #expect(deletion.deletedBy == deleter)
        #expect(deletion.deletedAt == deletedAt)
    }

    @Test("An edit timestamp round-trips, and its absence stays absent")
    func editTimestampRoundTrips() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let conversationID = ConversationID(data: Data(repeating: 8, count: 32))
        let editedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let edited = ConversationMessage(
            id: MessageID(value: 1), senderID: UUID(), content: .text("after"),
            date: Date(timeIntervalSince1970: 1_700_000_000), unreadSeq: 1,
            eventSequence: 2, lastEditedTs: editedAt
        )
        let untouched = ConversationMessage(
            id: MessageID(value: 2), senderID: UUID(), content: .text("hi"),
            date: Date(timeIntervalSince1970: 1_700_000_100), unreadSeq: 2, eventSequence: 1
        )

        try database.upsertConversationMessages([edited, untouched], conversationID: conversationID)

        let storedEdited = try #require(try database.message(id: MessageID(value: 1), conversationID: conversationID))
        let storedUntouched = try #require(try database.message(id: MessageID(value: 2), conversationID: conversationID))
        #expect(storedEdited.lastEditedTs == editedAt)
        #expect(storedUntouched.lastEditedTs == nil)
    }

    @Test("Looking up a message that isn't stored returns nil")
    func missingMessageReturnsNil() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let conversationID = ConversationID(data: Data(repeating: 9, count: 32))
        #expect(try database.message(id: MessageID(value: 99), conversationID: conversationID) == nil)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./Scripts/test.sh FlipcashTests/DatabaseConversationsTests
```

Expected: compile failure — `value of type 'Database' has no member 'message'`.

- [ ] **Step 3: Add the columns**

In `Schema.swift`, add to `ConversationMessageTable` after `clientMessageID`:

```swift
        let repliedToId    = Expression <UInt64?>        ("repliedToId")
        let lastEditedTs   = Expression <Double?>        ("lastEditedTs")
        let deletedBy      = Expression <UUID?>          ("deletedBy")
        let deletedAt      = Expression <Double?>        ("deletedAt")
```

`repliedToId` is added now, unused, because the schema version can only be bumped once per rebuild and the reply plan would otherwise force a second full resync on users. It is written as `nil` and read but ignored until then.

In the creation block, add the matching column declarations immediately before the `t.primaryKey(...)` line:

```swift
            t.column(conversationMessageTable.repliedToId)
            t.column(conversationMessageTable.lastEditedTs)
            t.column(conversationMessageTable.deletedBy)
            t.column(conversationMessageTable.deletedAt)
```

- [ ] **Step 4: Write and read the columns**

In `Database+Conversations.swift`, in `writeMessage`, replace the content switch's `.deleted` branch. The switch becomes:

```swift
        var deletedBy: UUID?
        var deletedAt: Double?
        switch message.content {
        case .text(let value):
            kind = 0
            text = value
        case .cash(let fiat):
            kind = 1
            quarks = fiat.onChain.quarks
            nativeAmount = fiat.native.value.description
            currency = fiat.native.currency
            mint = fiat.mint
        case .deleted(let deletion):
            kind = 2
            deletedBy = deletion.deletedBy
            deletedAt = deletion.deletedAt.timeIntervalSince1970
        }
```

(Keep the existing `var kind`/`text`/`quarks`/`nativeAmount`/`currency`/`mint` declarations above it exactly as they are; only the switch body and the two new `var`s change.)

Then add the four values to the setter list the insert builds, alongside the existing ones:

```swift
            // The reply plan fills this in; the column exists now so the schema is bumped once.
            table.repliedToId <- nil,
            table.lastEditedTs <- message.lastEditedTs?.timeIntervalSince1970,
            table.deletedBy <- deletedBy,
            table.deletedAt <- deletedAt,
```

In `conversationMessage(from:)`, replace the `case 2:` branch:

```swift
        case 2:
            content = .deleted(
                ConversationMessage.Deletion(
                    deletedBy: row[table.deletedBy],
                    deletedAt: row[table.deletedAt].map(Date.init(timeIntervalSince1970:)) ?? date
                )
            )
```

and pass the edit stamp into the `ConversationMessage` it returns:

```swift
            lastEditedTs: row[table.lastEditedTs].map(Date.init(timeIntervalSince1970:)),
```

(`date` is the local already decoded from `row[table.date]`; if the local is named differently in that function, use whatever name it has.)

- [ ] **Step 5: Add the single-message accessor**

In `Database+Conversations.swift`, next to `messageExists(id:conversationID:)`:

```swift
    /// The stored copy of one message, or `nil` if it is not in the local database. Mutations read
    /// through this rather than the display window, because `expected_event_sequence` must come
    /// from server truth, never from an optimistic overlay.
    func message(id: MessageID, conversationID: ConversationID) throws -> ConversationMessage? {
        let table = conversationMessageTable
        let query = table.table
            .filter(table.conversationId == conversationID.data && table.id == id.value)
            .limit(1)

        guard let row = try connection.pluck(query) else { return nil }
        return conversationMessage(from: row)
    }
```

If `messageExists` uses a different connection property name or a `try database.prepare` shape, match it exactly rather than the above.

- [ ] **Step 6: Bump the schema version**

In `Flipcash/Supporting Files/Info.plist`, change `SQLiteVersion` from `34` to `35`.

- [ ] **Step 7: Fix the existing tests that construct or match `.deleted`**

`FlipcashTests/Database/Database+ConversationsTests.swift` lines 405, 412, 434, 442, 457, 582, 587 and `FlipcashTests/ChatPreviewMappingTests.swift:60` use the payload-free case. Construction sites become:

```swift
content: .deleted(.init(deletedBy: nil, deletedAt: Date(timeIntervalSince1970: 0)))
```

and pattern-match sites become `message.isDeleted` (or `if case .deleted = message.content`, which still compiles for a payload-carrying case when the payload is ignored).

- [ ] **Step 8: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashTests/DatabaseConversationsTests FlipcashTests/ChatPreviewMappingTests
```

Expected: PASS for both suites.

- [ ] **Step 9: Commit**

```bash
git add Flipcash/Core/Controllers/Database Flipcash/Supporting\ Files/Info.plist FlipcashTests/Database/Database+ConversationsTests.swift FlipcashTests/ChatPreviewMappingTests.swift
git commit -m "feat(chat): persist message deletion detail and edit timestamps"
```

---

## Task 3: The capability model

**Files:**
- Create: `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessageAction.swift`
- Create: `FlipcashCore/Sources/FlipcashCore/Models/Chat/MessagePolicy.swift`
- Create: `FlipcashCore/Sources/FlipcashCore/Models/Conversation/MessageCapabilities.swift`
- Test: `FlipcashCore/Tests/FlipcashCoreTests/MessageCapabilitiesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `FlipcashCore/Tests/FlipcashCoreTests/MessageCapabilitiesTests.swift`:

```swift
import Testing
import Foundation
@testable import FlipcashCore

@Suite("Message capabilities")
struct MessageCapabilitiesTests {

    private let me = UUID()
    private let them = UUID()
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func text(_ body: String, from sender: UUID, eventSequence: UInt64 = 1, sentAgo: TimeInterval = 0) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: 1), senderID: sender, content: .text(body),
            date: now.addingTimeInterval(-sentAgo), unreadSeq: 1, eventSequence: eventSequence
        )
    }

    private func resolve(_ message: ConversationMessage, policy: MessagePolicy = .default) -> Set<ChatMessageAction> {
        MessageCapabilities.resolve(for: message, in: nil, as: me, policy: policy, now: now)
    }

    @Test("My own confirmed text can be copied, edited, and deleted")
    func ownTextIsFullyActionable() {
        #expect(resolve(text("hi", from: me)) == [.copy, .edit, .delete])
    }

    @Test("An unconfirmed message of mine offers nothing — it has no sequence to send as expected")
    func unconfirmedMessageOffersNothing() {
        #expect(resolve(text("hi", from: me, eventSequence: 0)).isEmpty)
    }

    @Test("Someone else's text can only be copied")
    func otherPersonsTextIsCopyOnly() {
        #expect(resolve(text("hi", from: them)) == [.copy])
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

    @Test("A cash message offers nothing in this scope — reply is the only capability it will ever have")
    func cashMessageOffersNothingYet() throws {
        let fiat = try ExchangedFiat.mock(quarks: 1_000_000)
        let cash = ConversationMessage(
            id: MessageID(value: 3), senderID: me, content: .cash(fiat), cashAction: .sent,
            date: now, unreadSeq: 1, eventSequence: 2
        )
        #expect(resolve(cash).isEmpty)
    }

    @Test("With an edit window configured, a message inside it stays editable")
    func messageInsideEditWindowIsEditable() {
        let policy = MessagePolicy(editWindow: 900, deletedPresentation: .placeholder)
        #expect(resolve(text("hi", from: me, sentAgo: 600), policy: policy) == [.copy, .edit, .delete])
    }

    @Test("With an edit window configured, a message past it can still be deleted but not edited")
    func messagePastEditWindowIsDeleteOnly() {
        let policy = MessagePolicy(editWindow: 900, deletedPresentation: .placeholder)
        #expect(resolve(text("hi", from: me, sentAgo: 1_200), policy: policy) == [.copy, .delete])
    }

    @Test("The default policy configures no edit window, so age never removes edit")
    func defaultPolicyHasNoEditWindow() {
        #expect(MessagePolicy.default.editWindow == nil)
        #expect(resolve(text("hi", from: me, sentAgo: 86_400)) == [.copy, .edit, .delete])
    }
}
```

If `ExchangedFiat` has no `mock(quarks:)` helper in the core test target, build one the way the existing core tests do — check `FlipcashCore/Tests/FlipcashCoreTests/` for the established construction and copy it verbatim into this test's helper rather than inventing a new factory.

- [ ] **Step 2: Run the test to verify it fails**

```bash
./Scripts/test.sh FlipcashCoreTests/MessageCapabilitiesTests
```

Expected: compile failure — `cannot find 'MessageCapabilities' in scope`.

- [ ] **Step 3: Write the three types**

`FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessageAction.swift`:

```swift
import Foundation

/// Something a person may do to a message. This is both the capability a policy grants and the row
/// the transcript's context menu renders, because the two are always the same set.
public enum ChatMessageAction: String, Hashable, Sendable, Codable, CaseIterable {
    case copy
    case reply
    case edit
    case delete
}

extension ChatMessageAction {

    /// The menu row's label.
    public var title: String {
        switch self {
        case .copy:   "Copy"
        case .reply:  "Reply"
        case .edit:   "Edit"
        case .delete: "Delete"
        }
    }

    /// Whether the menu should render this row in its destructive style.
    public var isDestructive: Bool {
        switch self {
        case .copy, .reply, .edit: false
        case .delete:              true
        }
    }
}
```

`FlipcashCore/Sources/FlipcashCore/Models/Chat/MessagePolicy.swift`:

```swift
import Foundation

/// How a deleted message occupies its place in the transcript.
public enum DeletedMessagePresentation: Hashable, Sendable, Codable {
    /// A muted bubble reading "You deleted this message" / "This message was deleted". Keeps the
    /// sender's side, the timestamp, and the grouping, so a reply quoting it still has a target.
    case placeholder
    /// The row is dropped entirely — the transcript's behaviour before deletion existed.
    case hidden
}

/// The tunables that govern what may be done to a message and how a deleted one is shown. Group
/// chats will eventually vary these per conversation; today every conversation gets `.default`.
public struct MessagePolicy: Hashable, Sendable {

    /// How long after sending a message stays editable, or `nil` for no limit. The server does not
    /// enforce a window today, so the default is `nil` — a client-side window would only hide an
    /// action the server would have accepted.
    public let editWindow: TimeInterval?
    public let deletedPresentation: DeletedMessagePresentation

    public init(editWindow: TimeInterval?, deletedPresentation: DeletedMessagePresentation) {
        self.editWindow = editWindow
        self.deletedPresentation = deletedPresentation
    }

    public static let `default` = MessagePolicy(editWindow: nil, deletedPresentation: .placeholder)
}
```

`FlipcashCore/Sources/FlipcashCore/Models/Conversation/MessageCapabilities.swift`:

```swift
import Foundation

/// Resolves what a person may do to a message. Pure — the same inputs always give the same answer,
/// which is what lets the transcript mapper run off the main actor.
public enum MessageCapabilities {

    /// The actions `selfUserID` may take on `message`.
    ///
    /// `conversation` is accepted but unread today: it is the seam a group-chat permissions model
    /// plugs into (an admin deleting another member's message, a read-only channel), and taking it
    /// now means adding that model does not change every call site. It is optional because the
    /// transcript can paint before the conversation record is loaded, and a message's own
    /// capabilities do not depend on it in a direct message.
    ///
    /// `now` is a parameter rather than `Date.now` so the result stays a function of its inputs.
    public static func resolve(
        for message: ConversationMessage,
        in conversation: Conversation?,
        as selfUserID: UserID,
        policy: MessagePolicy,
        now: Date
    ) -> Set<ChatMessageAction> {
        switch message.content {
        case .deleted:
            // Nothing is left to act on, and a tombstone must not be re-deleted.
            return []
        case .cash:
            // Reply is a cash message's only capability, and reply is not built yet.
            return []
        case .text:
            break
        }

        guard message.isFromSelf(selfUserID) else {
            return [.copy]
        }

        // An unconfirmed message has no `eventSequence` to send as `expected_event_sequence`, so no
        // mutation request can be built for it. Copy is withheld too, so the menu does not appear
        // and then grow rows the instant the send confirms.
        guard message.eventSequence > 0 else {
            return []
        }

        var capabilities: Set<ChatMessageAction> = [.copy, .delete]
        if let window = policy.editWindow {
            if now.timeIntervalSince(message.date) <= window {
                capabilities.insert(.edit)
            }
        } else {
            capabilities.insert(.edit)
        }
        return capabilities
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
./Scripts/test.sh FlipcashCoreTests/MessageCapabilitiesTests
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models FlipcashCore/Tests/FlipcashCoreTests/MessageCapabilitiesTests.swift
git commit -m "feat(chat): add the message capability model"
```

---

## Task 4: `ChatMessage` renders a tombstone and an edit marker

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessage.swift`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatItem+Differentiable.swift:35`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/LinkableBubbleView.swift:71-75`
- Test: `FlipcashTests/Chat/ChatBubbleViewTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `FlipcashTests/Chat/ChatBubbleViewTests.swift`:

```swift
@MainActor
@Suite("Chat bubble deleted and edited rendering")
struct ChatBubbleDeletedTests {

    @Test("A deleted bubble shows the tombstone copy")
    func deletedBubbleShowsCopy() {
        let text = ChatBubbleView.displayText(
            for: ChatMessage(id: "1", content: .deleted("You deleted this message"), sender: .me)
        )
        #expect(text?.string == "You deleted this message")
    }

    @Test("An edited bubble appends the edited marker after the body")
    func editedBubbleAppendsMarker() {
        let text = ChatBubbleView.displayText(
            for: ChatMessage(id: "1", content: .text("hello"), sender: .me, isEdited: true)
        )
        #expect(text?.string == "hello  Edited")
    }

    @Test("An unedited bubble is just its body")
    func uneditedBubbleIsPlain() {
        let text = ChatBubbleView.displayText(
            for: ChatMessage(id: "1", content: .text("hello"), sender: .me)
        )
        #expect(text?.string == "hello")
    }

    @Test("A cash row has no bubble text — it uses its own cell")
    func cashRowHasNoBubbleText() {
        let cash = ChatCashContent(amount: "$5.00", token: "Cash", flagImageName: nil, iconURL: nil, isTip: false)
        #expect(ChatBubbleView.displayText(for: ChatMessage(id: "1", content: .cash(cash), sender: .me)) == nil)
    }

    @Test("A deleted message reuses the plain text cell, so a delete reconfigures in place")
    func deletedReusesTextCell() {
        let deleted = ChatItem.message(ChatMessage(id: "1", content: .deleted("Message deleted"), sender: .other))
        let plain = ChatItem.message(ChatMessage(id: "1", text: "hi", sender: .other))
        #expect(deleted.differenceIdentifier == plain.differenceIdentifier)
    }
}
```

`differenceIdentifier` is on an `internal` extension in `FlipcashUI`; this file already uses `@testable import FlipcashUI`, so it resolves. Confirm the import list at the top of the file includes `@testable import FlipcashUI` and `import FlipcashCore`.

- [ ] **Step 2: Run the test to verify it fails**

```bash
./Scripts/test.sh FlipcashTests/ChatBubbleDeletedTests
```

Expected: compile failure — `type 'ChatMessage.Content' has no member 'deleted'`.

- [ ] **Step 3: Extend `ChatMessage`**

In `ChatMessage.swift`, add the content case and the two properties:

```swift
    public enum Content: Hashable, Sendable, Codable {
        case text(String)
        case cash(ChatCashContent)
        /// A deleted message's placeholder copy, already resolved for the viewer — "You deleted this
        /// message" or "This message was deleted". The mapper decides which; the view just draws it.
        case deleted(String)
    }
```

Add the stored properties after `linkPreview`:

```swift
    /// Whether to draw the muted "Edited" marker after the body.
    public let isEdited: Bool
    /// What the context menu offers for this row, already ordered. Empty means no menu.
    public let actions: [ChatMessageAction]
```

Extend both initialisers. The designated one:

```swift
    public init(
        id: String,
        content: Content,
        sender: Sender,
        isContinuationFromPrevious: Bool = false,
        isContinuedByNext: Bool = false,
        receipt: ChatReceipt? = nil,
        linkPreview: LinkPreview? = nil,
        isEdited: Bool = false,
        actions: [ChatMessageAction] = []
    ) {
        self.id = id
        self.content = content
        self.sender = sender
        self.isContinuationFromPrevious = isContinuationFromPrevious
        self.isContinuedByNext = isContinuedByNext
        self.receipt = receipt
        self.linkPreview = linkPreview
        self.isEdited = isEdited
        self.actions = actions
    }
```

and the text convenience initialiser gains the same two parameters with the same defaults, forwarding them to the designated one. Keep every existing parameter and its default exactly as it is — the defaults are what keep `ChatMotionSandbox.grouped(_:)` and the existing tests compiling untouched.

- [ ] **Step 4: Handle the new case in both content switches**

`ChatItem+Differentiable.swift`, in `cellReuseIdentifier`:

```swift
            case .message(let message):
                switch message.content {
                case .text:
                    message.linkPreview != nil ? ChatLinkMessageCell.reuseIdentifier : ChatMessageCell.reuseIdentifier
                case .deleted:
                    // Deliberately the same cell class as plain text: a message becoming a tombstone
                    // then diffs as an in-place reconfigure rather than a delete-and-insert.
                    ChatMessageCell.reuseIdentifier
                case .cash:
                    ChatCashCardCell.reuseIdentifier
                }
```

`LinkableBubbleView.swift`, in `configure(with:)`:

```swift
        switch message.content {
        case .text(let text):
            textView.text = text
        case .deleted(let placeholder):
            textView.text = placeholder
        case .cash:
            textView.text = nil
        }
```

- [ ] **Step 5: Render the text in `ChatBubbleView`**

In `ChatBubbleView.swift`, replace the content switch in `configure(with:)` with a call to a testable static, and add that static:

```swift
    public func configure(with message: ChatMessage) {
        label.attributedText = Self.displayText(for: message)

        background.apply(
            fill: BubbleBackgroundView.fill(isFromSelf: message.sender == .me),
            radii: BubbleBackgroundView.radii(
                isFromSelf: message.sender == .me,
                groupedAbove: message.isContinuationFromPrevious,
                groupedBelow: message.isContinuedByNext
            ),
            identity: message.id
        )
    }

    /// The bubble's rendered text: the body, a muted italic placeholder for a tombstone, and a muted
    /// "Edited" marker where the sender has revised the message. `nil` for cash rows, which use a
    /// dedicated cell rather than this bubble.
    public static func displayText(for message: ChatMessage) -> NSAttributedString? {
        let body: String
        let isPlaceholder: Bool
        switch message.content {
        case .text(let text):
            body = text
            isPlaceholder = false
        case .deleted(let placeholder):
            body = placeholder
            isPlaceholder = true
        case .cash:
            return nil
        }

        let bodyFont: UIFont = isPlaceholder
            ? .italicSystemFont(ofSize: 16)
            : .default(size: 16, weight: .medium)
        let bodyColor: UIColor = isPlaceholder ? UIColor.white.withAlphaComponent(0.55) : .white

        let result = NSMutableAttributedString(
            string: body,
            attributes: [.font: bodyFont, .foregroundColor: bodyColor]
        )

        if message.isEdited, !isPlaceholder {
            result.append(NSAttributedString(
                string: "  Edited",
                attributes: [
                    .font: UIFont.default(size: 12, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.5),
                ]
            ))
        }

        return result
    }
```

Delete the now-unused `label.font` and `label.textColor` lines from `setUp()` — the attributed string carries both. Keep `label.numberOfLines = 0`.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashTests/ChatBubbleDeletedTests FlipcashTests/ChatBubbleViewCornerTests FlipcashTests/ChatMessageCellAlignmentTests
```

Expected: PASS for all three suites — the two existing suites confirm the bubble's geometry did not shift.

- [ ] **Step 7: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessage.swift FlipcashUI/Sources/FlipcashUI/Chat FlipcashTests/Chat/ChatBubbleViewTests.swift
git commit -m "feat(chat): render deleted placeholders and edited markers in bubbles"
```

---

## Task 5: The transcript mapper emits tombstones, markers, and actions

**Files:**
- Modify: `Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift:52-140`
- Test: `FlipcashTests/Chat/ChatMessageMappingTests.swift`

- [ ] **Step 1: Write the failing test**

Append to the existing `ChatMessageMappingTests` suite in `FlipcashTests/Chat/ChatMessageMappingTests.swift`:

```swift
    private func deleted(_ id: UInt64, _ sender: UUID, deletedBy: UUID?, after offset: TimeInterval) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: sender,
            content: .deleted(.init(deletedBy: deletedBy, deletedAt: base.addingTimeInterval(offset))),
            date: base.addingTimeInterval(offset), unreadSeq: id, eventSequence: id
        )
    }

    @Test("In placeholder mode my own deletion reads as mine")
    func placeholderNamesTheDeleter() {
        let items = ChatItem.from(
            [deleted(1, me, deletedBy: me, after: 0)],
            selfUserID: me,
            deletedPresentation: .placeholder
        )
        #expect(messageRows(items).first?.content == .deleted("You deleted this message"))
    }

    @Test("In placeholder mode someone else's deletion reads impersonally")
    func placeholderIsImpersonalForOthers() {
        let items = ChatItem.from(
            [deleted(1, them, deletedBy: them, after: 0)],
            selfUserID: me,
            deletedPresentation: .placeholder
        )
        #expect(messageRows(items).first?.content == .deleted("This message was deleted"))
    }

    @Test("A tombstone never anchors the delivery receipt, even when it is my newest row")
    func tombstoneDoesNotAnchorReceipt() {
        let items = ChatItem.from(
            [text(1, me, "hello", after: 0), deleted(2, me, deletedBy: me, after: 60)],
            selfUserID: me,
            deletedPresentation: .placeholder
        )
        let rows = messageRows(items)
        #expect(rows.count == 2)
        #expect(rows[0].receipt?.displayText == "Delivered")
        #expect(rows[1].receipt == nil)
    }

    @Test("An edited message is flagged for the edited marker")
    func editedMessageIsFlagged() {
        var edited = text(1, me, "after", after: 0)
        edited = ConversationMessage(
            id: edited.id, senderID: edited.senderID, content: edited.content,
            date: edited.date, unreadSeq: edited.unreadSeq, eventSequence: 2,
            lastEditedTs: base.addingTimeInterval(30)
        )
        let items = ChatItem.from([edited], selfUserID: me)
        #expect(messageRows(items).first?.isEdited == true)
    }

    @Test("Actions come back in menu order, never in set order")
    func actionsAreOrdered() {
        let items = ChatItem.from(
            [text(1, me, "hi", after: 0)],
            selfUserID: me,
            capabilities: { _ in [.delete, .edit, .copy] }
        )
        #expect(messageRows(items).first?.actions == [.copy, .edit, .delete])
    }
```

Keep the existing `deletedTombstoneIsDroppedCleanly` test as it is — it now pins the `.hidden` default rather than an unconditional filter, which is exactly what it should assert.

- [ ] **Step 2: Run the test to verify it fails**

```bash
./Scripts/test.sh FlipcashTests/ChatMessageMappingTests
```

Expected: compile failure — `extra arguments 'deletedPresentation', 'capabilities' in call`.

- [ ] **Step 3: Extend the mapper**

In `ChatItem+Conversation.swift`, change the signature and body of `from(_:selfUserID:...)`:

```swift
    nonisolated static func from(
        _ messages: [ConversationMessage],
        selfUserID: UserID,
        gap: TimeInterval = 15 * 60,
        counterpartRead: (pointer: MessageID, date: Date?)? = nil,
        suppressReceiptFor: String? = nil,
        cashBranding: (ExchangedFiat) -> (token: String, iconURL: URL?) = { _ in ("Cash", nil) },
        deletedPresentation: DeletedMessagePresentation = .hidden,
        capabilities: (ConversationMessage) -> Set<ChatMessageAction> = { _ in [] }
    ) -> [ChatItem] {
        let messages: [ConversationMessage] = switch deletedPresentation {
        case .hidden:      messages.filter { !$0.isDeleted }
        case .placeholder: messages
        }

        // A tombstone has nothing to acknowledge, so it must not take the receipt from the last
        // message that does.
        let latestSentFromSelfID = messages.last {
            $0.isFromSelf(selfUserID) && $0.status == .sent && !$0.isDeleted
        }?.stableID
```

Leave the loop's separator and grouping logic untouched. Replace the content switch:

```swift
            let content: ChatMessage.Content
            let linkPreview: LinkPreview?
            switch message.content {
            case .text(let text):
                content = .text(text)
                linkPreview = detectedLink(in: text)
            case .cash(let fiat):
                let branding = cashBranding(fiat)
                content = .cash(
                    ChatCashContent(
                        amount: fiat.native.formatted(showOfKind: .short),
                        token: branding.token,
                        flagImageName: fiat.native.currency.flagName,
                        iconURL: branding.iconURL,
                        isTip: message.cashAction == .tipped
                    )
                )
                linkPreview = nil
            case .deleted(let deletion):
                content = .deleted(
                    deletion.deletedBy == selfUserID
                        ? "You deleted this message"
                        : "This message was deleted"
                )
                linkPreview = nil
            }
```

Keep the existing `.cash` branch's body exactly as it currently reads in the file — the version above is illustrative of placement; do not rewrite the amount formatting or the flag lookup.

Then, where the row is appended:

```swift
            items.append(
                .message(
                    ChatMessage(
                        id: message.stableID,
                        content: content,
                        sender: isFromSelf ? .me : .other,
                        isContinuationFromPrevious: groupedAbove,
                        isContinuedByNext: groupedBelow,
                        receipt: receipt,
                        linkPreview: linkPreview,
                        isEdited: message.lastEditedTs != nil && !message.isDeleted,
                        actions: orderedActions(capabilities(message))
                    )
                )
            )
```

Add, next to `detectedLink(in:)`:

```swift
    /// Menu order is fixed here, not at the call site — a `Set` has no order, and the context menu
    /// must not shuffle its rows between renders of the same message.
    private static func orderedActions(_ capabilities: Set<ChatMessageAction>) -> [ChatMessageAction] {
        [.copy, .reply, .edit, .delete].filter(capabilities.contains)
    }
```

Note for whoever adds an edit window later: `capabilities` is a closure so the mapper stays pure. An edit window makes the resolved set time-dependent, which means the transcript would need re-mapping on a timer to drop `.edit` as the window expires. That is safe today only because `MessagePolicy.default.editWindow` is `nil`.

- [ ] **Step 4: Run the test to verify it passes**

```bash
./Scripts/test.sh FlipcashTests/ChatMessageMappingTests
```

Expected: PASS, including the pre-existing `deletedTombstoneIsDroppedCleanly`.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift FlipcashTests/Chat/ChatMessageMappingTests.swift
git commit -m "feat(chat): map tombstones, edit markers, and message actions"
```

---

## Task 6: Wire the policy through the load coordinator

**Files:**
- Modify: `Flipcash/Core/Screens/Conversation/ConversationLoadCoordinator.swift`

`Inputs` is `Equatable` and short-circuits the remap, so anything the mapper now reads has to participate in that equality or the transcript will go stale.

- [ ] **Step 1: Add the inputs**

In `ConversationLoadCoordinator.swift`, extend `Inputs`:

```swift
    struct Inputs: Equatable, Sendable {
        var messages: [ConversationMessage]
        var selfUserID: UserID
        var counterpartPointer: MessageID?
        var counterpartReadDate: Date?
        var suppressReceiptFor: String?
        var isTyping: Bool
        var profileCard: ChatProfileCard?
        var branding: [PublicKey: Branding]
        var conversation: Conversation?
        var policy: MessagePolicy

        struct Branding: Equatable, Sendable {
            var token: String
            var iconURL: URL?
        }
    }
```

In `currentInputs()`, capture the conversation once and pass it through, replacing the existing `read` line and the `Inputs(...)` construction:

```swift
        let conversation = controller.conversation(withID: conversationID)
        let read = conversation?.counterpartReadReceipt(excluding: controller.selfUserID)
```

and add to the `Inputs(...)` call, after `branding: branding`:

```swift
            conversation: conversation,
            policy: .default
```

In `map(_:)`, pass the two new arguments to `ChatItem.from`:

```swift
            deletedPresentation: inputs.policy.deletedPresentation,
            capabilities: { message in
                MessageCapabilities.resolve(
                    for: message,
                    in: inputs.conversation,
                    as: inputs.selfUserID,
                    policy: inputs.policy,
                    now: message.date
                )
            }
```

`now: message.date` is deliberate: the default policy has no edit window, so `now` is unread, and passing the message's own date keeps `map` a pure function of `Inputs`. When an edit window is introduced, this becomes a real clock and `map` stops being pure — that change must come with a re-map trigger, not just a different argument here.

- [ ] **Step 2: Build to verify it compiles**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the mapping tests to verify nothing regressed**

```bash
./Scripts/test.sh FlipcashTests/ChatMessageMappingTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Flipcash/Core/Screens/Conversation/ConversationLoadCoordinator.swift
git commit -m "feat(chat): resolve message capabilities in the transcript coordinator"
```

---

## Task 7: The optimistic mutation overlay

**Files:**
- Create: `FlipcashCore/Sources/FlipcashCore/Models/Conversation/MutationEntry.swift`
- Modify: `FlipcashCore/Sources/FlipcashCore/Models/Conversation/ConversationStore.swift`
- Test: `FlipcashCore/Tests/FlipcashCoreTests/ConversationStoreMutationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `FlipcashCore/Tests/FlipcashCoreTests/ConversationStoreMutationTests.swift`:

```swift
import Testing
import Foundation
@testable import FlipcashCore

@Suite("ConversationStore mutation overlay")
struct ConversationStoreMutationTests {

    private let sender = UUID()

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private func message(_ id: UInt64, _ text: String, eventSequence: UInt64) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: sender, content: .text(text),
            date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: id, eventSequence: eventSequence
        )
    }

    private func texts(_ messages: [ConversationMessage]) -> [String] {
        messages.map {
            switch $0.content {
            case .text(let value): value
            case .deleted:         "<deleted>"
            case .cash:            "<cash>"
            }
        }
    }

    @Test("An edit overlay replaces the stored text")
    func editOverlayReplacesText() {
        var store = ConversationStore()
        let id = conversationID(1)
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .edited("after"), expectedSequence: 5),
            in: id
        )

        let displayed = store.displayedMessages(
            for: id,
            over: [message(1, "one", eventSequence: 4), message(2, "before", eventSequence: 5)]
        )
        #expect(texts(displayed) == ["one", "after"])
    }

    @Test("An edit overlay marks the message as edited so the marker shows immediately")
    func editOverlayMarksEdited() {
        var store = ConversationStore()
        let id = conversationID(1)
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .edited("after"), expectedSequence: 5),
            in: id
        )

        let displayed = store.displayedMessages(for: id, over: [message(2, "before", eventSequence: 5)])
        #expect(displayed.first?.lastEditedTs != nil)
    }

    @Test("A delete overlay turns the message into a tombstone attributed to its sender")
    func deleteOverlayTombstones() {
        var store = ConversationStore()
        let id = conversationID(1)
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .deleted, expectedSequence: 5),
            in: id
        )

        let displayed = store.displayedMessages(for: id, over: [message(2, "before", eventSequence: 5)])
        guard case .deleted(let deletion) = displayed.first?.content else {
            Issue.record("expected a tombstone")
            return
        }
        #expect(deletion.deletedBy == sender)
    }

    @Test("A stored row that out-versions the overlay wins — the server's answer landed")
    func newerStoredRowBeatsTheOverlay() {
        var store = ConversationStore()
        let id = conversationID(1)
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .edited("mine"), expectedSequence: 5),
            in: id
        )

        let displayed = store.displayedMessages(for: id, over: [message(2, "theirs", eventSequence: 6)])
        #expect(texts(displayed) == ["theirs"])
    }

    @Test("Dropping the overlay restores the stored text")
    func droppingOverlayRestoresStoredText() {
        var store = ConversationStore()
        let id = conversationID(1)
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .edited("after"), expectedSequence: 5),
            in: id
        )
        store.dropMutation(for: MessageID(value: 2), in: id)

        let displayed = store.displayedMessages(for: id, over: [message(2, "before", eventSequence: 5)])
        #expect(texts(displayed) == ["before"])
    }

    @Test("An overlay in one conversation does not leak into another")
    func overlayIsScopedToItsConversation() {
        var store = ConversationStore()
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .edited("after"), expectedSequence: 5),
            in: conversationID(1)
        )

        let displayed = store.displayedMessages(for: conversationID(2), over: [message(2, "before", eventSequence: 5)])
        #expect(texts(displayed) == ["before"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./Scripts/test.sh FlipcashCoreTests/ConversationStoreMutationTests
```

Expected: compile failure — `cannot find 'MutationEntry' in scope`.

- [ ] **Step 3: Write `MutationEntry`**

Create `FlipcashCore/Sources/FlipcashCore/Models/Conversation/MutationEntry.swift`:

```swift
import Foundation

/// An edit or delete that has been issued but not yet confirmed, overlaid on the stored message so
/// the transcript reflects it immediately. The mirror image of `PendingEntry`, which does the same
/// job for a message that has not been sent yet.
public struct MutationEntry: Hashable, Sendable {

    public enum Kind: Hashable, Sendable {
        case edited(String)
        case deleted
    }

    public let messageID: MessageID
    public let kind: Kind
    /// The `eventSequence` the message carried when the mutation was issued — the same value sent as
    /// `expected_event_sequence`. A stored row that exceeds it is the server's newer answer, and the
    /// overlay stops applying.
    public let expectedSequence: UInt64

    public init(messageID: MessageID, kind: Kind, expectedSequence: UInt64) {
        self.messageID = messageID
        self.kind = kind
        self.expectedSequence = expectedSequence
    }
}
```

- [ ] **Step 4: Compose the overlay in the store**

In `ConversationStore.swift`, add the storage next to `pendingByConversation`:

```swift
    private var mutationsByConversation: [ConversationID: [MessageID: MutationEntry]] = [:]
```

Add the two mutators next to `insertPending`:

```swift
    /// Records an optimistic edit or delete. One per message — reissuing replaces the previous entry.
    public mutating func applyMutation(_ entry: MutationEntry, in conversationID: ConversationID) {
        mutationsByConversation[conversationID, default: [:]][entry.messageID] = entry
    }

    /// Removes the overlay, whether because the server confirmed it, overrode it, or refused it.
    public mutating func dropMutation(for messageID: MessageID, in conversationID: ConversationID) {
        mutationsByConversation[conversationID]?.removeValue(forKey: messageID)
        if mutationsByConversation[conversationID]?.isEmpty == true {
            mutationsByConversation.removeValue(forKey: conversationID)
        }
    }
```

Change `displayedMessages` to overlay before it composes the pending sends. Only its first two lines change:

```swift
    public func displayedMessages(for conversationID: ConversationID, over confirmed: [ConversationMessage]) -> [ConversationMessage] {
        let confirmed = overlaid(confirmed, in: conversationID)
        guard let pending = pendingByConversation[conversationID], !pending.isEmpty else { return confirmed }
```

The rest of the function is untouched. Add the private helper directly beneath it:

```swift
    /// Replaces each stored message that has a live mutation with its optimistic form. A mutation
    /// whose message has already advanced past `expectedSequence` no longer applies: the server's
    /// answer has landed, and whatever it says wins.
    private func overlaid(_ confirmed: [ConversationMessage], in conversationID: ConversationID) -> [ConversationMessage] {
        guard let mutations = mutationsByConversation[conversationID], !mutations.isEmpty else { return confirmed }

        return confirmed.map { message in
            guard let entry = mutations[message.id], message.eventSequence <= entry.expectedSequence else {
                return message
            }
            switch entry.kind {
            case .edited(let text):
                // The stamp only drives the "Edited" marker, so the message's own date stands in for
                // the server's — using a live clock here would make the store's output time-dependent.
                return message.replacingContent(.text(text), lastEditedTs: message.lastEditedTs ?? message.date)
            case .deleted:
                // Delete is only ever offered on your own message, so its sender is its deleter.
                return message.replacingContent(
                    .deleted(.init(deletedBy: message.senderID, deletedAt: message.date)),
                    lastEditedTs: message.lastEditedTs
                )
            }
        }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashCoreTests/ConversationStoreMutationTests FlipcashCoreTests/ConversationStoreTests
```

Expected: PASS for both — the existing store suite confirms the pending-send composition is unchanged.

- [ ] **Step 6: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models/Conversation FlipcashCore/Tests/FlipcashCoreTests/ConversationStoreMutationTests.swift
git commit -m "feat(chat): overlay optimistic edits and deletes in the conversation store"
```

---

## Task 8: The edit and delete RPCs

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Clients/Flip API/Services/ChatMessagingService.swift`
- Modify: `FlipcashCore/Sources/FlipcashCore/Clients/Flip API/FlipClient+Chat.swift`
- Modify: `Flipcash/Core/Controllers/FlipClient+Protocols.swift:70-87`
- Modify: `FlipcashTests/TestSupport/MockConversations.swift`

A `CONFLICT` response carries the message state that won. Discarding it would leave the transcript showing the losing copy until the next delta, so the result type keeps both the message and the fact that it was a conflict.

- [ ] **Step 1: Add the result type and error enums**

At the top of `ChatMessagingService.swift`, below the existing imports and above the service type:

```swift
/// The outcome of an edit or delete: the message state the server now holds, and whether that state
/// came back as a conflict — meaning another client's change won and this one did not apply.
public struct MessageMutation: Sendable, Equatable {
    public let message: ConversationMessage
    public let isConflict: Bool

    public init(message: ConversationMessage, isConflict: Bool) {
        self.message = message
        self.isConflict = isConflict
    }
}
```

Next to the existing error enums (around line 214):

```swift
public enum ErrorEditMessage: Int, Error {
    case ok
    case denied
    case messageNotFound
    case cannotEdit
    case conflict
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorDeleteMessage: Int, Error {
    case ok
    case denied
    case messageNotFound
    case cannotDelete
    case conflict
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}
```

The positional cases must stay in this order — the raw values map directly onto the proto's `Result` enum (`OK = 0`, `DENIED = 1`, `MESSAGE_NOT_FOUND = 2`, `CANNOT_EDIT`/`CANNOT_DELETE = 3`, `CONFLICT = 4`).

Add the conformances wherever the file's other error enums declare theirs (`ErrorAdvancePointer`, `ErrorNotifyIsTyping`) — match that file's existing pattern for `ServerError` and `TransportClassifiableError` exactly, including how `reportingLevel` is written.

- [ ] **Step 2: Write the two RPC wrappers**

In `ChatMessagingService`, next to `sendMessage`:

```swift
    func editMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        messageID: MessageID,
        text: String,
        expectedEventSequence: UInt64,
        completion: @Sendable @escaping (Result<MessageMutation, ErrorEditMessage>) -> Void
    ) {
        let request = Flipcash_Messaging_V1_EditMessageRequest.with {
            $0.chatID = conversationID.proto
            $0.messageID = messageID.proto
            $0.content = [.with { $0.text = .with { $0.text = text } }]
            $0.expectedEventSequence = expectedEventSequence
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.editMessage(request, options: .unaryDefault)
                let error = ErrorEditMessage(rawValue: response.result.rawValue) ?? .unknown
                switch error {
                case .ok, .conflict:
                    guard response.hasMessage, let message = ConversationMessage(response.message) else {
                        logger.error("Edit message response carried no message")
                        await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                        return
                    }
                    await MainActor.run {
                        completion(.success(MessageMutation(message: message, isConflict: error == .conflict)))
                    }
                case .denied, .messageNotFound, .cannotEdit, .unknown, .transportFailure, .cancelled, .rejected:
                    logger.error("Failed to edit message")
                    await MainActor.run { completion(.failure(error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func deleteMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        messageID: MessageID,
        expectedEventSequence: UInt64,
        completion: @Sendable @escaping (Result<MessageMutation, ErrorDeleteMessage>) -> Void
    ) {
        let request = Flipcash_Messaging_V1_DeleteMessageRequest.with {
            $0.chatID = conversationID.proto
            $0.messageID = messageID.proto
            $0.expectedEventSequence = expectedEventSequence
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.deleteMessage(request, options: .unaryDefault)
                let error = ErrorDeleteMessage(rawValue: response.result.rawValue) ?? .unknown
                switch error {
                case .ok, .conflict:
                    guard response.hasMessage, let message = ConversationMessage(response.message) else {
                        logger.error("Delete message response carried no message")
                        await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                        return
                    }
                    await MainActor.run {
                        completion(.success(MessageMutation(message: message, isConflict: error == .conflict)))
                    }
                case .denied, .messageNotFound, .cannotDelete, .unknown, .transportFailure, .cancelled, .rejected:
                    logger.error("Failed to delete message")
                    await MainActor.run { completion(.failure(error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
```

- [ ] **Step 3: Add the async wrappers**

In `FlipClient+Chat.swift`, matching the file's existing continuation pattern:

```swift
    public func editMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        messageID: MessageID,
        text: String,
        expectedEventSequence: UInt64
    ) async throws -> MessageMutation {
        try await withCheckedThrowingContinuation { continuation in
            chatMessagingService.editMessage(
                owner: owner,
                conversationID: conversationID,
                messageID: messageID,
                text: text,
                expectedEventSequence: expectedEventSequence
            ) { continuation.resume(with: $0) }
        }
    }

    public func deleteMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        messageID: MessageID,
        expectedEventSequence: UInt64
    ) async throws -> MessageMutation {
        try await withCheckedThrowingContinuation { continuation in
            chatMessagingService.deleteMessage(
                owner: owner,
                conversationID: conversationID,
                messageID: messageID,
                expectedEventSequence: expectedEventSequence
            ) { continuation.resume(with: $0) }
        }
    }
```

- [ ] **Step 4: Extend the protocol and the mock**

In `Flipcash/Core/Controllers/FlipClient+Protocols.swift`, add to `ConversationMessaging`:

```swift
    func editMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, text: String, expectedEventSequence: UInt64) async throws -> MessageMutation
    func deleteMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, expectedEventSequence: UInt64) async throws -> MessageMutation
```

In `FlipcashTests/TestSupport/MockConversations.swift`, add the recorded calls and stubs. Follow the file's existing `_x` + `lock.withLock` accessor pattern exactly:

```swift
    struct Edited: Sendable, Equatable {
        let conversationID: ConversationID
        let messageID: MessageID
        let text: String
        let expectedEventSequence: UInt64
    }

    struct Deleted: Sendable, Equatable {
        let conversationID: ConversationID
        let messageID: MessageID
        let expectedEventSequence: UInt64
    }

    private var _edited: [Edited] = []
    var edited: [Edited] { lock.withLock { _edited } }

    private var _deleted: [Deleted] = []
    var deleted: [Deleted] { lock.withLock { _deleted } }

    private var _editResult: MessageMutation?
    var editResult: MessageMutation? {
        get { lock.withLock { _editResult } }
        set { lock.withLock { _editResult = newValue } }
    }

    private var _editError: (any Error)?
    var editError: (any Error)? {
        get { lock.withLock { _editError } }
        set { lock.withLock { _editError = newValue } }
    }

    private var _deleteResult: MessageMutation?
    var deleteResult: MessageMutation? {
        get { lock.withLock { _deleteResult } }
        set { lock.withLock { _deleteResult = newValue } }
    }

    private var _deleteError: (any Error)?
    var deleteError: (any Error)? {
        get { lock.withLock { _deleteError } }
        set { lock.withLock { _deleteError = newValue } }
    }

    func editMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, text: String, expectedEventSequence: UInt64) async throws -> MessageMutation {
        lock.withLock {
            _edited.append(Edited(conversationID: conversationID, messageID: messageID, text: text, expectedEventSequence: expectedEventSequence))
        }
        if let editError { throw editError }
        guard let editResult else {
            throw ErrorEditMessage.unknown
        }
        return editResult
    }

    func deleteMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, expectedEventSequence: UInt64) async throws -> MessageMutation {
        lock.withLock {
            _deleted.append(Deleted(conversationID: conversationID, messageID: messageID, expectedEventSequence: expectedEventSequence))
        }
        if let deleteError { throw deleteError }
        guard let deleteResult else {
            throw ErrorDeleteMessage.unknown
        }
        return deleteResult
    }
```

- [ ] **Step 5: Build to verify it compiles**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Clients Flipcash/Core/Controllers/FlipClient+Protocols.swift FlipcashTests/TestSupport/MockConversations.swift
git commit -m "feat(chat): add edit and delete message RPCs"
```

---

## Task 9: The controller's mutation loop

**Files:**
- Create: `Flipcash/Core/Controllers/ConversationController+MessageMutations.swift`
- Modify: `Flipcash/Core/Controllers/ConversationController.swift` (`messageWriteOperations`, new `mutationAlert`)
- Test: `FlipcashTests/ConversationMutationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `FlipcashTests/ConversationMutationTests.swift`. Build the controller exactly the way `FlipcashTests/ConversationControllerTests.swift` does — open that file, copy its setup helper verbatim into this one, and use it here rather than assembling a different one.

```swift
import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Conversation message mutations")
struct ConversationMutationTests {

    /// The controller plus the two things a mutation test has to reach into: the transport it talks
    /// to, and the database it reads sequences from. Built the same way `ConversationControllerTests`
    /// builds its controller, with the database held rather than discarded.
    private struct Harness {
        let controller: ConversationController
        let messaging: MockConversations
        let database: Database
        let conversationID: ConversationID
    }

    private func makeHarness(selfUserID: UserID = UUID()) throws -> Harness {
        let mock = MockConversations()
        let database = try Database.makeTemp().database
        let controller = ConversationController(
            fetching: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: selfUserID,
            typingHeartbeatInterval: .seconds(3),
            incomingTypingExpiry: .seconds(10)
        )
        return Harness(controller: controller, messaging: mock, database: database, conversationID: .test(1))
    }

    private func stored(_ id: UInt64, _ text: String, sender: UUID, eventSequence: UInt64) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: sender, content: .text(text),
            date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: id, eventSequence: eventSequence
        )
    }

    @Test("Editing sends the message's stored event sequence as the expected one")
    func editSendsStoredSequence() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        let original = stored(1, "before", sender: harness.controller.selfUserID, eventSequence: 4)
        try harness.database.upsertConversationMessages([original], conversationID: conversationID)

        harness.messaging.editResult = MessageMutation(
            message: stored(1, "after", sender: harness.controller.selfUserID, eventSequence: 5),
            isConflict: false
        )

        let outcome = await harness.controller.edit(messageID: MessageID(value: 1), in: conversationID, to: "after")

        #expect(outcome == .applied)
        #expect(harness.messaging.edited.count == 1)
        #expect(harness.messaging.edited.first?.expectedEventSequence == 4)
        #expect(harness.messaging.edited.first?.text == "after")
    }

    @Test("A successful edit persists the server's copy")
    func editPersistsServerCopy() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        try harness.database.upsertConversationMessages(
            [stored(1, "before", sender: harness.controller.selfUserID, eventSequence: 4)],
            conversationID: conversationID
        )
        harness.messaging.editResult = MessageMutation(
            message: stored(1, "after", sender: harness.controller.selfUserID, eventSequence: 5),
            isConflict: false
        )

        _ = await harness.controller.edit(messageID: MessageID(value: 1), in: conversationID, to: "after")

        let persisted = try #require(try harness.database.message(id: MessageID(value: 1), conversationID: conversationID))
        #expect(persisted.content == .text("after"))
        #expect(persisted.eventSequence == 5)
    }

    @Test("A conflict persists the state that won and reports the conflict")
    func editConflictPersistsWinner() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        try harness.database.upsertConversationMessages(
            [stored(1, "before", sender: harness.controller.selfUserID, eventSequence: 4)],
            conversationID: conversationID
        )
        harness.messaging.editResult = MessageMutation(
            message: stored(1, "someone else won", sender: harness.controller.selfUserID, eventSequence: 6),
            isConflict: true
        )

        let outcome = await harness.controller.edit(messageID: MessageID(value: 1), in: conversationID, to: "mine")

        #expect(outcome == .conflicted)
        let persisted = try #require(try harness.database.message(id: MessageID(value: 1), conversationID: conversationID))
        #expect(persisted.content == .text("someone else won"))
        #expect(harness.controller.mutationAlert?.kind == .conflict)
    }

    @Test("A transport failure reverts the overlay and leaves the stored text alone")
    func editFailureRevertsOverlay() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        try harness.database.upsertConversationMessages(
            [stored(1, "before", sender: harness.controller.selfUserID, eventSequence: 4)],
            conversationID: conversationID
        )
        harness.messaging.editError = ErrorEditMessage.transportFailure

        let outcome = await harness.controller.edit(messageID: MessageID(value: 1), in: conversationID, to: "after")

        #expect(outcome == .failed)
        let displayed = harness.controller.windowedMessages(for: conversationID, startingAt: nil, limit: 50)
        #expect(displayed.first?.content == .text("before"))
        #expect(harness.controller.mutationAlert?.kind == .failure)
    }

    @Test("An unconfirmed message cannot be edited — there is no sequence to send")
    func editRejectsUnconfirmedMessage() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        try harness.database.upsertConversationMessages(
            [stored(1, "before", sender: harness.controller.selfUserID, eventSequence: 0)],
            conversationID: conversationID
        )

        let outcome = await harness.controller.edit(messageID: MessageID(value: 1), in: conversationID, to: "after")

        #expect(outcome == .failed)
        #expect(harness.messaging.edited.isEmpty)
    }

    @Test("Deleting sends the stored sequence and persists the tombstone")
    func deletePersistsTombstone() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        let me = harness.controller.selfUserID
        try harness.database.upsertConversationMessages(
            [stored(1, "before", sender: me, eventSequence: 4)],
            conversationID: conversationID
        )
        harness.messaging.deleteResult = MessageMutation(
            message: ConversationMessage(
                id: MessageID(value: 1), senderID: me,
                content: .deleted(.init(deletedBy: me, deletedAt: Date(timeIntervalSince1970: 10))),
                date: Date(timeIntervalSince1970: 1), unreadSeq: 1, eventSequence: 5
            ),
            isConflict: false
        )

        let outcome = await harness.controller.delete(messageID: MessageID(value: 1), in: conversationID)

        #expect(outcome == .applied)
        #expect(harness.messaging.deleted.first?.expectedEventSequence == 4)
        let persisted = try #require(try harness.database.message(id: MessageID(value: 1), conversationID: conversationID))
        #expect(persisted.isDeleted)
    }
}
```

`.test(1)` is the `ConversationID` helper `ConversationControllerTests` already uses; `MockDMContactNaming` is the naming stub from the same test support. Neither needs changing.

- [ ] **Step 2: Run the test to verify it fails**

```bash
./Scripts/test.sh FlipcashTests/ConversationMutationTests
```

Expected: compile failure — `value of type 'ConversationController' has no member 'edit'`.

- [ ] **Step 3: Add the alert type and the write-operation names**

In `ConversationController.swift`, next to the other observable state (near `messageRevision`):

```swift
    /// Set when a mutation needs to be reported to the person who made it. The screen presents it
    /// and clears it. `nil` means there is nothing to report.
    var mutationAlert: MutationAlert?

    /// A mutation the user has to be told about, because the transcript alone will not explain it.
    struct MutationAlert: Equatable, Identifiable {
        enum Kind: String, Equatable {
            /// Another client's change won; the transcript now shows that change, not this one.
            case conflict
            /// The request never applied; the transcript has reverted.
            case failure
        }

        let action: ChatMessageAction
        let kind: Kind

        var id: String { "\(action.rawValue)-\(kind.rawValue)" }
    }
```

Add the two operation names to `messageWriteOperations` — without them `persist(operation:)` will not bump `messageRevision`, and the transcript will keep showing the pre-mutation window:

```swift
    private let messageWriteOperations: Set<String> = [
        "upsert-messages", "apply-chat-events", "delta-batch", "load-messages",
        "load-older", "send-message", "reset-resync", "edit-message", "delete-message",
    ]
```

(Match the existing declaration's exact type and formatting; only the two new entries are added.)

- [ ] **Step 4: Write the mutation methods**

Create `Flipcash/Core/Controllers/ConversationController+MessageMutations.swift`:

```swift
import Foundation
import FlipcashCore

/// What a mutation attempt did.
enum MutationOutcome: Equatable {
    /// The server accepted it; the transcript shows the result.
    case applied
    /// Another client's change won; the transcript shows that change instead.
    case conflicted
    /// Nothing applied; the transcript has reverted to what it showed before.
    case failed
}

@MainActor
extension ConversationController {

    /// Replaces a message's text. The transcript updates immediately from an overlay; the server's
    /// answer then replaces it, whether that answer is the edit or somebody else's.
    @discardableResult
    func edit(messageID: MessageID, in conversationID: ConversationID, to text: String) async -> MutationOutcome {
        guard let current = confirmedMessage(messageID, in: conversationID), current.eventSequence > 0 else {
            logger.error("Refusing to edit a message with no confirmed sequence", metadata: [
                "conversationID": "\(conversationID)",
                "messageID": "\(messageID)",
            ])
            return .failed
        }

        store.applyMutation(
            MutationEntry(messageID: messageID, kind: .edited(text), expectedSequence: current.eventSequence),
            in: conversationID
        )
        bumpMessageRevision()

        do {
            let outcome = try await messaging.editMessage(
                owner: owner,
                conversationID: conversationID,
                messageID: messageID,
                text: text,
                expectedEventSequence: current.eventSequence
            )
            settle(outcome, messageID: messageID, in: conversationID, operation: "edit-message")
            if outcome.isConflict {
                mutationAlert = MutationAlert(action: .edit, kind: .conflict)
                return .conflicted
            }
            return .applied
        } catch {
            store.dropMutation(for: messageID, in: conversationID)
            bumpMessageRevision()
            logger.error("Failed to edit conversation message", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to edit conversation message")
            mutationAlert = MutationAlert(action: .edit, kind: .failure)
            return .failed
        }
    }

    /// Deletes a message for everyone in the conversation. The row is not removed — it becomes a
    /// tombstone, so message ordering stays gapless and a reply quoting it still has a target.
    @discardableResult
    func delete(messageID: MessageID, in conversationID: ConversationID) async -> MutationOutcome {
        guard let current = confirmedMessage(messageID, in: conversationID), current.eventSequence > 0 else {
            logger.error("Refusing to delete a message with no confirmed sequence", metadata: [
                "conversationID": "\(conversationID)",
                "messageID": "\(messageID)",
            ])
            return .failed
        }

        store.applyMutation(
            MutationEntry(messageID: messageID, kind: .deleted, expectedSequence: current.eventSequence),
            in: conversationID
        )
        bumpMessageRevision()

        do {
            let outcome = try await messaging.deleteMessage(
                owner: owner,
                conversationID: conversationID,
                messageID: messageID,
                expectedEventSequence: current.eventSequence
            )
            settle(outcome, messageID: messageID, in: conversationID, operation: "delete-message")
            if outcome.isConflict {
                mutationAlert = MutationAlert(action: .delete, kind: .conflict)
                return .conflicted
            }
            return .applied
        } catch {
            store.dropMutation(for: messageID, in: conversationID)
            bumpMessageRevision()
            logger.error("Failed to delete conversation message", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to delete conversation message")
            mutationAlert = MutationAlert(action: .delete, kind: .failure)
            return .failed
        }
    }

    /// The stored copy. The overlay is deliberately not consulted: `expected_event_sequence` has to
    /// come from server truth, or a second edit would send the sequence the first one optimistically
    /// assumed and conflict against the server every time.
    private func confirmedMessage(_ messageID: MessageID, in conversationID: ConversationID) -> ConversationMessage? {
        do {
            return try database.message(id: messageID, conversationID: conversationID)
        } catch {
            logger.error("Failed to read message for mutation", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            return nil
        }
    }

    /// Persists whatever the server says the message now is and drops the overlay. Identical for an
    /// accepted mutation and a conflict — a conflict's payload is the state that won, which is
    /// exactly what has to land locally. There is no retry: reissuing would clobber the change that
    /// beat this one.
    private func settle(
        _ outcome: MessageMutation,
        messageID: MessageID,
        in conversationID: ConversationID,
        operation: String
    ) {
        _ = persist(operation: operation) {
            try database.upsertConversationMessages([outcome.message], conversationID: conversationID)
        }
        store.dropMutation(for: messageID, in: conversationID)
        refreshFeedPreview(for: conversationID)
        persistConversation(conversationID)
    }
}
```

`store`, `database`, `owner`, `messaging`, `logger`, `persist(operation:)`, `refreshFeedPreview(for:)`, and `persistConversation(_:)` are all `private` on `ConversationController` today. Relax each to the file-default (drop the `private` keyword) so this extension can reach them — do not make them `public`.

`bumpMessageRevision()` does not exist yet. Add it to `ConversationController.swift` next to `messageRevision`:

```swift
    /// Forces the transcript to re-read its window. `persist(operation:)` does this for database
    /// writes; an overlay change writes nothing, so it has to say so explicitly.
    func bumpMessageRevision() {
        messageRevision &+= 1
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashTests/ConversationMutationTests FlipcashTests/ConversationControllerTests
```

Expected: PASS for both.

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Core/Controllers FlipcashTests/ConversationMutationTests.swift
git commit -m "feat(chat): reconcile optimistic message edits and deletes"
```

---

## Task 10: The composer knows whether it is writing or editing

**Files:**
- Create: `Flipcash/Core/Screens/Conversation/ComposerModel.swift`
- Modify: `Flipcash/Core/Screens/Conversation/ConversationBottomBar.swift`
- Test: `FlipcashTests/Chat/ComposerModelTests.swift`

`ConversationBarModel` keeps `isComposing`, which is about focus and drives the Send Cash morph and the dismiss gate. The draft and the mode move to `ComposerModel`, because they are one concern with three pieces of state.

- [ ] **Step 1: Write the failing test**

Create `FlipcashTests/Chat/ComposerModelTests.swift`:

```swift
import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Composer mode")
struct ComposerModelTests {

    @Test("A fresh composer is writing a new message")
    func freshComposerIsNew() {
        let composer = ComposerModel()
        #expect(composer.mode == .new)
        #expect(composer.draft.isEmpty)
        #expect(!composer.canSubmit)
    }

    @Test("Beginning an edit loads the message's text and stashes the unsent draft")
    func beginEditingStashesDraft() {
        let composer = ComposerModel()
        composer.draft = "half-typed"
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "original")

        #expect(composer.mode == .editing(messageID: MessageID(value: 3), stableID: "3"))
        #expect(composer.draft == "original")
    }

    @Test("Cancelling an edit restores the stashed draft")
    func cancellingRestoresDraft() {
        let composer = ComposerModel()
        composer.draft = "half-typed"
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "original")
        composer.draft = "changed my mind"
        composer.endEditing()

        #expect(composer.mode == .new)
        #expect(composer.draft == "half-typed")
    }

    @Test("Submission trims whitespace and refuses an empty draft")
    func submissionTrims() {
        let composer = ComposerModel()
        composer.draft = "  hello  "
        #expect(composer.canSubmit)
        #expect(composer.submission == "hello")

        composer.draft = "   "
        #expect(!composer.canSubmit)
        #expect(composer.submission == nil)
    }

    @Test("An edit that leaves the text unchanged cannot be submitted")
    func unchangedEditCannotSubmit() {
        let composer = ComposerModel()
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "original")
        #expect(!composer.canSubmit)

        composer.draft = "original edited"
        #expect(composer.canSubmit)
    }

    @Test("Clearing after a send empties the draft and stays in new-message mode")
    func clearAfterSend() {
        let composer = ComposerModel()
        composer.draft = "sent"
        composer.clear()

        #expect(composer.draft.isEmpty)
        #expect(composer.mode == .new)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./Scripts/test.sh FlipcashTests/ComposerModelTests
```

Expected: compile failure — `cannot find 'ComposerModel' in scope`.

- [ ] **Step 3: Write `ComposerModel`**

Create `Flipcash/Core/Screens/Conversation/ComposerModel.swift`:

```swift
import Foundation
import Observation
import FlipcashCore

/// What the composer is writing, and the text it holds. Editing borrows the same field as a new
/// message, so the unsent draft is stashed while an edit is in progress and put back if the edit is
/// cancelled.
@MainActor
@Observable
final class ComposerModel {

    enum Mode: Equatable {
        case new
        /// `stableID` is the transcript row's identity, kept alongside the message id so the screen
        /// can highlight the row being edited without re-deriving it.
        case editing(messageID: MessageID, stableID: String)
    }

    private(set) var mode: Mode = .new
    var draft = ""

    /// The unsent new-message draft, held while an edit occupies the field.
    @ObservationIgnored private var stashedDraft = ""
    /// The text the message had when the edit began, so an unchanged edit can be refused.
    @ObservationIgnored private var originalText = ""

    /// The trimmed text to submit, or `nil` if there is nothing worth submitting. An edit that
    /// matches the original is nothing worth submitting.
    var submission: String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch mode {
        case .new:
            return trimmed
        case .editing:
            return trimmed == originalText ? nil : trimmed
        }
    }

    var canSubmit: Bool { submission != nil }

    /// Switches the field to editing an existing message, stashing whatever was being written.
    func beginEditing(messageID: MessageID, stableID: String, currentText: String) {
        if case .new = mode {
            stashedDraft = draft
        }
        mode = .editing(messageID: messageID, stableID: stableID)
        originalText = currentText
        draft = currentText
    }

    /// Leaves editing and restores the stashed draft.
    func endEditing() {
        guard case .editing = mode else { return }
        mode = .new
        originalText = ""
        draft = stashedDraft
        stashedDraft = ""
    }

    /// Empties the field after a successful send.
    func clear() {
        mode = .new
        originalText = ""
        stashedDraft = ""
        draft = ""
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
./Scripts/test.sh FlipcashTests/ComposerModelTests
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Move the draft out of `ConversationBarModel`**

In `ConversationBottomBar.swift`, `ConversationBarModel` sheds `draft` and `canSend`:

```swift
/// Shared state for the unified bottom bar: the focus-driven `isComposing` flag that drives the
/// Send Cash morph and the screen's interactive-dismiss gate. The draft itself lives in
/// `ComposerModel`, which also knows whether it is a new message or an edit.
@MainActor @Observable final class ConversationBarModel {
    var isComposing = false
}
```

`ConversationBottomBar` gains `let composer: ComposerModel` alongside `let model: ConversationBarModel`, and passes it to `ConversationComposer`.

`ConversationComposer` takes `@Bindable var composer: ComposerModel` in addition to its existing `@Bindable var model: ConversationBarModel`. Its body changes in four places:

```swift
            TextField("Message", text: $composer.draft, axis: .vertical)
```

```swift
            if composer.canSubmit {
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.default(size: 16, weight: .bold))
                        .foregroundStyle(Color.textAction)
                        .frame(width: 34, height: 34)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(composer.mode == .new ? "Send" : "Save")
                .accessibilityIdentifier("send-message-button")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
```

```swift
        .animation(Self.sendButtonSpring, value: composer.canSubmit)
```

```swift
        .onChange(of: composer.draft) { _, text in
            guard let conversationID else { return }
            conversationController.draftDidChange(text, in: conversationID)
        }
```

and `send()` becomes `submit()`:

```swift
    private func submit() {
        guard let conversationID, let text = composer.submission else { return }

        switch composer.mode {
        case .new:
            composer.clear()
            isFocused = true
            Task { await conversationController.send(text, to: conversationID) }
        case .editing(let messageID, _):
            composer.endEditing()
            isFocused = true
            Task { await conversationController.edit(messageID: messageID, in: conversationID, to: text) }
        }
    }
```

Add the edit banner above the field. Wrap the composer's returned view in a `VStack(alignment: .leading, spacing: 8)` and put this first:

```swift
        if case .editing = composer.mode {
            HStack(spacing: 10) {
                Image(systemName: SystemSymbol.pencil.rawValue)
                    .font(.default(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                Text("Editing message")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: 0)
                Button {
                    composer.endEditing()
                } label: {
                    Image(systemName: SystemSymbol.xmark.rawValue)
                        .font(.default(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel editing")
                .accessibilityIdentifier("cancel-edit-button")
            }
            .padding(.horizontal, 14)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
```

and animate the whole stack on the mode:

```swift
        .animation(barMorphSpring, value: composer.mode)
```

If `Color.textSecondary` or `Font.appTextSmall` do not exist under those names, use whatever the file's neighbours use for muted secondary text — grep `ConversationBottomBar.swift` and `ConversationScreen.swift` for the established token.

- [ ] **Step 6: Update the three call sites**

`ChatScreenRepresentable.swift` gains `let composer: ComposerModel` and passes it to `ConversationBottomBar` wherever `barModel` is passed today (lines 43 and 110 reference `barModel`; add `composer` beside it in both the stored properties and the bar construction).

`ConversationScreen.swift` adds `@State private var composer = ComposerModel()` beside `@State private var barModel = ConversationBarModel()` and passes `composer: composer` in the `ChatScreenRepresentable(...)` call at line 201.

- [ ] **Step 7: Build to verify it compiles**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED. If `SystemSymbol.pencil` is missing, that case is added in Task 11 — add it now rather than waiting:

```swift
    case pencil = "pencil"
    case trash = "trash"
```

in `FlipcashUI/Sources/FlipcashUI/Theme/Image+Symbols.swift`, in the `SystemSymbol` enum.

- [ ] **Step 8: Commit**

```bash
git add Flipcash/Core/Screens/Conversation FlipcashUI/Sources/FlipcashUI/Theme/Image+Symbols.swift FlipcashTests/Chat/ComposerModelTests.swift
git commit -m "feat(chat): give the composer an editing mode"
```

---

## Task 11: The context menu is built from the message's actions

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift:503-528`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatScreenViewController.swift:55-84`
- Modify: `FlipcashUI/Sources/FlipcashUI/Theme/Image+Symbols.swift` (if Task 10 did not already add the cases)
- Test: `FlipcashTests/Chat/ChatMessageActionMenuTests.swift`

- [ ] **Step 1: Write the failing test**

Create `FlipcashTests/Chat/ChatMessageActionMenuTests.swift`:

```swift
import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatViewController action menu")
struct ChatMessageActionMenuTests {

    private func loadedController(_ items: [ChatItem]) -> ChatViewController {
        let controller = ChatViewController()
        controller.loadViewIfNeeded()
        controller.update(items: items)
        return controller
    }

    private func configuration(_ controller: ChatViewController, at index: Int) -> UIContextMenuConfiguration? {
        controller.collectionView(
            controller.collectionView,
            contextMenuConfigurationForItemAt: IndexPath(item: index, section: 0),
            point: .zero
        )
    }

    private func titles(_ configuration: UIContextMenuConfiguration?) -> [String] {
        guard let provider = configuration?.actionProvider,
              let menu = provider([]) as? UIMenu else { return [] }
        return menu.children.compactMap { ($0 as? UIAction)?.title }
    }

    @Test("The menu renders exactly the actions the message carries, in order")
    func menuMatchesActions() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", text: "hi", sender: .me, actions: [.copy, .edit, .delete]))
        ])
        #expect(titles(configuration(controller, at: 0)) == ["Copy", "Edit", "Delete"])
    }

    @Test("A message with no actions offers no menu")
    func noActionsMeansNoMenu() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", text: "hi", sender: .other, actions: []))
        ])
        #expect(configuration(controller, at: 0) == nil)
    }

    @Test("Delete is marked destructive")
    func deleteIsDestructive() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", text: "hi", sender: .me, actions: [.copy, .delete]))
        ])
        guard let provider = configuration(controller, at: 0)?.actionProvider,
              let menu = provider([]) as? UIMenu,
              let delete = menu.children.compactMap({ $0 as? UIAction }).first(where: { $0.title == "Delete" }) else {
            Issue.record("expected a Delete action")
            return
        }
        #expect(delete.attributes.contains(.destructive))
    }

    @Test("Copy writes the body to the pasteboard without notifying the screen")
    func copyStaysLocal() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", text: "copy me", sender: .me, actions: [.copy]))
        ])
        var notified: [(String, ChatMessageAction)] = []
        controller.onMessageAction = { notified.append(($0, $1)) }

        guard let provider = configuration(controller, at: 0)?.actionProvider,
              let menu = provider([]) as? UIMenu,
              let copy = menu.children.first as? UIAction else {
            Issue.record("expected a Copy action")
            return
        }
        copy.performWithSender(nil, target: nil)

        #expect(UIPasteboard.general.string == "copy me")
        #expect(notified.isEmpty)
    }

    @Test("Edit and Delete report the row's id to the screen")
    func editAndDeleteNotify() {
        let controller = loadedController([
            .message(ChatMessage(id: "row-7", text: "hi", sender: .me, actions: [.edit, .delete]))
        ])
        var notified: [(String, ChatMessageAction)] = []
        controller.onMessageAction = { notified.append(($0, $1)) }

        guard let provider = configuration(controller, at: 0)?.actionProvider,
              let menu = provider([]) as? UIMenu else {
            Issue.record("expected a menu")
            return
        }
        for action in menu.children.compactMap({ $0 as? UIAction }) {
            action.performWithSender(nil, target: nil)
        }

        #expect(notified.map(\.0) == ["row-7", "row-7"])
        #expect(notified.map(\.1) == [.edit, .delete])
    }

    @Test("A deleted placeholder offers no menu")
    func tombstoneOffersNoMenu() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", content: .deleted("This message was deleted"), sender: .other))
        ])
        #expect(configuration(controller, at: 0) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./Scripts/test.sh FlipcashTests/ChatMessageActionMenuTests
```

Expected: compile failure — `value of type 'ChatViewController' has no member 'onMessageAction'`.

- [ ] **Step 3: Rewrite the menu**

In `ChatViewController.swift`, add the callback next to the existing ones:

```swift
    /// Fired when a context-menu action other than Copy is chosen, with the row's id. Copy is handled
    /// here — it needs nothing the transcript does not already hold.
    public var onMessageAction: ((String, ChatMessageAction) -> Void)?
```

Replace `contextMenuConfigurationForItemAt`:

```swift
    public override func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isUpdating else { return nil }

        guard case .message(let message) = items[indexPath.item], !message.actions.isEmpty else { return nil }

        let body: String? = if case .text(let text) = message.content { text } else { nil }

        isShowingContextMenu = true
        freezeInset()

        let identifier = "\(indexPath.section)|\(indexPath.item)" as NSString
        let rowID = message.id
        let actions = message.actions
        let handler = onMessageAction

        return UIContextMenuConfiguration(identifier: identifier, previewProvider: nil) { _ in
            let children = actions.map { action in
                UIAction(
                    title: action.title,
                    image: UIImage(systemName: action.menuSymbol.rawValue),
                    attributes: action.isDestructive ? .destructive : []
                ) { _ in
                    switch action {
                    case .copy:
                        if let body { UIPasteboard.general.string = body }
                    case .reply, .edit, .delete:
                        handler?(rowID, action)
                    }
                }
            }
            return UIMenu(title: "", children: children)
        }
    }
```

Add the symbol mapping at the bottom of the same file:

```swift
private extension ChatMessageAction {

    /// The menu row's glyph. Lives here rather than on the action itself because `SystemSymbol` is
    /// this module's symbol registry, and `ChatMessageAction` is a core model.
    var menuSymbol: SystemSymbol {
        switch self {
        case .copy:   .doc
        case .reply:  .arrowLeft
        case .edit:   .pencil
        case .delete: .trash
        }
    }
}
```

If `SystemSymbol` has no `arrowLeft`, use whichever left/reply-facing arrow case it does have — `.reply` never reaches the menu in this scope, so the choice is provisional and the reply plan will settle it.

Confirm `SystemSymbol` has `pencil` and `trash` (Task 10 may have added them); if not, add:

```swift
    case pencil = "pencil"
    case trash = "trash"
```

- [ ] **Step 4: Pass the callback through the screen controller**

In `ChatScreenViewController.swift`, next to the other pass-throughs:

```swift
    public var onMessageAction: ((String, ChatMessageAction) -> Void)? {
        get { transcript.onMessageAction }
        set { transcript.onMessageAction = newValue }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashTests/ChatMessageActionMenuTests FlipcashTests/ChatMessageCopyTests
```

Expected: PASS for the new suite. `ChatMessageCopyTests` will now fail on its text-message cases, because those fixtures build messages with no `actions` — update each of them to pass `actions: [.copy]`, keeping the assertions unchanged. Its cash and date-separator cases still pass untouched. Re-run both suites until green.

- [ ] **Step 6: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI FlipcashTests/Chat/ChatMessageActionMenuTests.swift FlipcashTests/Chat/ChatMessageCopyTests.swift
git commit -m "feat(chat): build the transcript context menu from message actions"
```

---

## Task 12: The screen acts on the chosen action

**Files:**
- Modify: `Flipcash/Core/Screens/Conversation/ChatScreenRepresentable.swift`
- Modify: `Flipcash/Core/Screens/Conversation/ConversationScreen.swift`

- [ ] **Step 1: Plumb the callback**

In `ChatScreenRepresentable.swift`, add the stored property beside the other callbacks:

```swift
    let onMessageAction: (String, ChatMessageAction) -> Void
```

and assign it in both `makeUIViewController` and `updateUIViewController`, beside the existing assignments:

```swift
        controller.onMessageAction = onMessageAction
```

- [ ] **Step 2: Handle the action**

In `ConversationScreen.swift`, pass the handler into the representable at the call site around line 201:

```swift
                onMessageAction: handleMessageAction,
```

and add the handler to the view:

```swift
    /// Routes a context-menu choice. Copy never arrives here — the transcript handles it locally.
    private func handleMessageAction(_ stableID: String, _ action: ChatMessageAction) {
        guard let message = coordinator?.loader.messages.first(where: { $0.stableID == stableID }) else { return }

        switch action {
        case .copy:
            break
        case .reply:
            break // Reply is a separate scope; the menu does not offer it yet.
        case .edit:
            guard case .text(let text) = message.content else { return }
            composer.beginEditing(messageID: message.id, stableID: stableID, currentText: text)
        case .delete:
            confirmDelete(message.id)
        }
    }

    private func confirmDelete(_ messageID: MessageID) {
        guard let conversationID = conversation?.id else { return }

        session.dialogItem = DialogItem.alert(
            title: "Delete Message",
            subtitle: "This message will be deleted for everyone in this chat."
        ) {
            DialogAction.destructive("Delete") {
                Task { await conversationController.delete(messageID: messageID, in: conversationID) }
            }
            DialogAction.cancel()
        }
    }
```

`conversation?.id` and `conversationController` are illustrative names — use whichever the surrounding file already has in scope for the conversation id and the controller (the `ChatScreenRepresentable(...)` call at line 201 passes both, so read the exact names from there).

- [ ] **Step 3: Present the mutation alert**

Add to the same view's modifier chain, next to the existing `.interactiveDismissDisabled(barModel.isComposing)`:

```swift
        .onChange(of: conversationController.mutationAlert) { _, alert in
            guard let alert else { return }
            session.dialogItem = DialogItem.alert(
                title: alert.title,
                subtitle: alert.subtitle
            ) {
                DialogAction.okay(kind: .destructive) {
                    conversationController.mutationAlert = nil
                }
            }
        }
```

Check `DialogAction.okay(kind:options:)`'s signature before writing this — if it takes no trailing action closure, clear `mutationAlert` in the dialog's dismissal instead, following whatever the surrounding screens do to react to a dialog closing.

Add the copy to `ConversationController.MutationAlert` in `ConversationController.swift`:

```swift
        var title: String {
            switch kind {
            case .conflict: "Message Changed"
            case .failure:
                switch action {
                case .edit:                "Couldn't Edit Message"
                case .delete:              "Couldn't Delete Message"
                case .copy, .reply:        "Something Went Wrong"
                }
            }
        }

        var subtitle: String {
            switch kind {
            case .conflict:
                "This message changed somewhere else, so your change wasn't applied. The chat now shows the latest version."
            case .failure:
                "Check your connection and try again."
            }
        }
```

- [ ] **Step 4: Build to verify it compiles**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Screens/Conversation Flipcash/Core/Controllers/ConversationController.swift
git commit -m "feat(chat): wire message edit and delete into the conversation screen"
```

---

## Task 13: Switch the transcript to placeholder tombstones

**Files:**
- Modify: `Flipcash/Core/Screens/Conversation/ConversationLoadCoordinator.swift`
- Test: `FlipcashTests/Chat/ChatMessageMappingTests.swift`

Everything up to here has run with `MessagePolicy.default`, whose `deletedPresentation` is `.placeholder` — but the coordinator was wired in Task 6 and the mapper defaults to `.hidden` only for callers that pass nothing. This task is the verification that the two agree, and the one place to flip if the answer is wrong.

- [ ] **Step 1: Confirm the wiring**

Read `ConversationLoadCoordinator.map(_:)` and check it passes `deletedPresentation: inputs.policy.deletedPresentation`. Read `MessagePolicy.default` and check `deletedPresentation` is `.placeholder`. If both hold, the transcript already renders placeholders and there is nothing to change.

- [ ] **Step 2: Add the end-to-end assertion**

Append to `FlipcashTests/Chat/ChatMessageMappingTests.swift`:

```swift
    @Test("The default policy shows a placeholder, so a deleted row keeps its place")
    func defaultPolicyShowsPlaceholder() {
        #expect(MessagePolicy.default.deletedPresentation == .placeholder)

        let items = ChatItem.from(
            [text(1, them, "hi", after: 0), deleted(2, them, deletedBy: them, after: 30)],
            selfUserID: me,
            deletedPresentation: MessagePolicy.default.deletedPresentation
        )
        let rows = messageRows(items)
        #expect(rows.count == 2)
        #expect(rows[1].content == .deleted("This message was deleted"))
        #expect(rows[0].isContinuedByNext)
    }
```

- [ ] **Step 3: Run the test to verify it passes**

```bash
./Scripts/test.sh FlipcashTests/ChatMessageMappingTests
```

Expected: PASS.

- [ ] **Step 4: Run the whole affected set**

```bash
./Scripts/test.sh FlipcashCoreTests/MessageCapabilitiesTests FlipcashCoreTests/ConversationStoreMutationTests FlipcashCoreTests/ConversationStoreTests FlipcashCoreTests/ConversationMessageMetadataTests FlipcashTests/ChatMessageMappingTests FlipcashTests/ChatMessageActionMenuTests FlipcashTests/ChatMessageCopyTests FlipcashTests/ChatBubbleDeletedTests FlipcashTests/ComposerModelTests FlipcashTests/ConversationMutationTests
```

Expected: PASS for every suite.

- [ ] **Step 5: Commit**

```bash
git add FlipcashTests/Chat/ChatMessageMappingTests.swift
git commit -m "test(chat): pin the default tombstone presentation end to end"
```

---

## What this plan does not do

- **Reply.** No quote rendering, no swipe gesture, no tap-to-jump. `repliedToId` is added to the schema and `ChatMessageAction.reply` to the enum, both unused, so the reply plan does not force a second schema bump or an enum change.
- **Reactions.** Out of scope per the spec, with the inline `.small` `UIMenu` slot still unclaimed.
- **Delete for me.** Delete is for everyone only; the spec models the delete kinds as a list so a second kind can be added without reshaping the menu.
- **A configured edit window.** `MessagePolicy.editWindow` exists and is honoured by `MessageCapabilities`, but the default is `nil`. Turning one on requires a re-map trigger, because it makes the resolved capability set time-dependent — see the note in Task 5.
- **Group permissions.** `MessageCapabilities.resolve` takes the conversation and ignores it. That parameter is the seam.
