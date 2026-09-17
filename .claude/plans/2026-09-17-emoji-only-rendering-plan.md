# Emoji-Only Message Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A chat message whose whole body is one to three emoji renders as the emoji alone at 48pt — no bubble, no border, no wash — the way iMessage draws one, while keeping its side, receipt line, avatar gutter, tap-to-retry, swipe-to-reply and context menu.

**Architecture:** Detection is a pure function in `FlipcashCore` (`EmojiOnlyDetector`), called by the transcript mapper. The mapper splits today's single grouping pair into two: `isContinuationFromPrevious`/`isContinuedByNext` keep their values and now mean the *author* run only (name + gutter face), while new `joinsBubbleAbove`/`joinsBubbleBelow` carry the *bubble* run (flattened inner corners, tight row gap). A bare emoji row breaks the bubble run on both sides without touching attribution. A third flag, `isEmojiOnly`, plus a computed `rendersAsLargeEmoji`, select a new `ChatEmojiMessageCell` through the existing `cellReuseIdentifier` → `differenceIdentifier` path, so editing a message into or out of emoji-only diffs as delete+insert.

**Tech Stack:** Swift 6.1, UIKit (`UICollectionView` + ChatLayout), DifferenceKit, Swift Testing (`import Testing`, `@Suite`/`@Test`, `#expect` — never XCTest), SwiftUI only for `UnevenRoundedRectangle` geometry.

**Spec:** `.claude/plans/2026-09-17-emoji-only-rendering.md`

---

## File Structure

**Created**
| File | Responsibility |
|---|---|
| `FlipcashCore/Sources/FlipcashCore/Models/Chat/EmojiOnlyDetector.swift` | Pure "is this body 1–3 emoji?" test |
| `FlipcashCore/Tests/FlipcashCoreTests/EmojiOnlyDetectorTests.swift` | Detector unit tests |
| `FlipcashCore/Tests/FlipcashCoreTests/ChatMessageRenderingTests.swift` | `rendersAsLargeEmoji` gating |
| `FlipcashUI/Sources/FlipcashUI/Chat/LargeEmojiView.swift` | The bare 48pt emoji body + its own attention flash |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatEmojiMessageCell.swift` | `ChatColumnCell` subclass hosting `LargeEmojiView` |
| `FlipcashTests/Chat/ChatEmojiMessageCellTests.swift` | Cell: no bubble chrome, font size, "Edited" placement |
| `FlipcashTests/Chat/ChatItemCellSelectionTests.swift` | `cellReuseIdentifier` mapping |

**Modified**
| File | Change |
|---|---|
| `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessage.swift` | Three stored flags + `rendersAsLargeEmoji` |
| `Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift` | Computes the three flags |
| `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatPreviewMapping.swift` | Sets `isEmojiOnly` for the notification preview |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatItem+Differentiable.swift` | Emoji cell in the class decision |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatBubbleView.swift` | Radii read `joinsBubble*` |
| `FlipcashUI/Sources/FlipcashUI/Chat/LinkableBubbleView.swift` | Radii read `joinsBubble*` |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatCashCardCell.swift` | Radii read `joinsBubble*` |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift` | Row gap reads `joinsBubbleBelow`; registers + configures the emoji cell |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatMotion.swift` | Owns the attention keyframe |
| `FlipcashUI/Sources/FlipcashUI/Chat/BubbleBackgroundView.swift` | Uses `ChatMotion.attentionFlash`; `raise` no-ops without a shape |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatColumnCell.swift` | Bottom slot becomes a metadata row (Edited + receipt) |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatReceiptView.swift` | `trailingPadding` promoted to the view |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatScrollBenchmark.swift`, `ChatMotionSandbox.swift`, previews | Mirror the new flags |
| `FlipcashTests/Chat/ChatViewControllerTests.swift`, `ChatChangesetFlatteningTests.swift`, `ChatTranscriptDiffFuzzTests.swift`, `ChatMessageMappingTests.swift` | Fixtures + new cases |

**Order:** detection → model → mapper → consumers → motion → view → column → cell → wiring → preview cache. Every task ends on a green build.

---

### Task 1: `EmojiOnlyDetector`

**Files:**
- Create: `FlipcashCore/Sources/FlipcashCore/Models/Chat/EmojiOnlyDetector.swift`
- Test: `FlipcashCore/Tests/FlipcashCoreTests/EmojiOnlyDetectorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `FlipcashCore/Tests/FlipcashCoreTests/EmojiOnlyDetectorTests.swift`:

```swift
//
//  EmojiOnlyDetectorTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("EmojiOnlyDetector")
struct EmojiOnlyDetectorTests {

    @Test("One, two and three emoji qualify")
    func upToThreeQualify() {
        #expect(EmojiOnlyDetector.isEmojiOnly("👍"))
        #expect(EmojiOnlyDetector.isEmojiOnly("👍😀"))
        #expect(EmojiOnlyDetector.isEmojiOnly("👍😀🎉"))
    }

    @Test("A fourth emoji disqualifies")
    func fourIsTooMany() {
        #expect(!EmojiOnlyDetector.isEmojiOnly("👍😀🎉🔥"))
    }

    @Test("Whitespace around and between emoji is ignored")
    func whitespaceIsIgnored() {
        #expect(EmojiOnlyDetector.isEmojiOnly(" 👍 👍 \n"))
    }

    @Test("Emoji mixed with text does not qualify")
    func emojiPlusTextFails() {
        #expect(!EmojiOnlyDetector.isEmojiOnly("👍 nice"))
        #expect(!EmojiOnlyDetector.isEmojiOnly("nice 👍"))
    }

    @Test("Composed sequences count as one emoji each")
    func composedSequencesQualify() {
        #expect(EmojiOnlyDetector.isEmojiOnly("👨‍👩‍👧‍👦"))   // ZWJ family
        #expect(EmojiOnlyDetector.isEmojiOnly("👍🏽"))          // skin-tone modifier
        #expect(EmojiOnlyDetector.isEmojiOnly("🇺🇸"))          // regional-indicator flag
        #expect(EmojiOnlyDetector.isEmojiOnly("#️⃣"))          // keycap
        #expect(EmojiOnlyDetector.isEmojiOnly("👨‍👩‍👧‍👦👍🏽🇺🇸"))   // three of them together
    }

    @Test("Characters that carry the emoji property but render as text do not qualify")
    func emojiPropertyAloneIsNotEnough() {
        #expect(!EmojiOnlyDetector.isEmojiOnly("1"))
        #expect(!EmojiOnlyDetector.isEmojiOnly("#"))
        #expect(!EmojiOnlyDetector.isEmojiOnly("*"))
        #expect(!EmojiOnlyDetector.isEmojiOnly("e\u{0301}"))  // letter + combining mark
    }

    @Test("Empty and whitespace-only bodies do not qualify")
    func emptyDoesNotQualify() {
        #expect(!EmojiOnlyDetector.isEmojiOnly(""))
        #expect(!EmojiOnlyDetector.isEmojiOnly("   \n "))
    }

    @Test("The limit is a parameter")
    func limitIsConfigurable() {
        #expect(EmojiOnlyDetector.isEmojiOnly("👍😀🎉🔥", limit: 4))
        #expect(!EmojiOnlyDetector.isEmojiOnly("👍😀", limit: 1))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./Scripts/test.sh FlipcashCoreTests/EmojiOnlyDetectorTests
```

Expected: compile failure — `cannot find 'EmojiOnlyDetector' in scope`.

- [ ] **Step 3: Write the implementation**

Create `FlipcashCore/Sources/FlipcashCore/Models/Chat/EmojiOnlyDetector.swift`:

```swift
//
//  EmojiOnlyDetector.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Whether a message body is nothing but a handful of emoji — the transcript draws one of those
/// bare and enlarged instead of in a bubble. Pure and synchronous, like `LinkDetector`: the mapper
/// runs it on every remap, so it walks at most `limit + 1` grapheme clusters before bailing.
public enum EmojiOnlyDetector {

    /// True when `text` is 1...`limit` emoji and nothing else. Whitespace around and between them is
    /// ignored, so "👍 👍" qualifies.
    public static func isEmojiOnly(_ text: String, limit: Int = 3) -> Bool {
        var count = 0
        for cluster in text {
            if cluster.isWhitespace { continue }
            guard isEmojiCluster(cluster) else { return false }
            count += 1
            // Bail on the one past the limit rather than walking a long message to its end.
            if count > limit { return false }
        }
        return count > 0
    }

    /// One grapheme cluster that renders as an emoji.
    ///
    /// `isEmoji` alone is too broad — `1`, `#` and `*` all carry it, each being the base of a keycap
    /// sequence, and a bare `unicodeScalars.count > 1` test would admit a letter with a combining
    /// mark. What separates a real emoji is default emoji presentation, an explicit U+FE0F variation
    /// selector, or the keycap combining mark itself (`#⃣` is U+0023 U+20E3 and carries no U+FE0F).
    /// Flags, ZWJ families and skin-tone modifiers all pass on the first test: Swift groups each into
    /// a single `Character` whose first scalar already has emoji presentation.
    private static func isEmojiCluster(_ cluster: Character) -> Bool {
        guard let first = cluster.unicodeScalars.first, first.properties.isEmoji else { return false }
        return first.properties.isEmojiPresentation
            || cluster.unicodeScalars.contains { $0 == "\u{FE0F}" || $0 == "\u{20E3}" }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashCoreTests/EmojiOnlyDetectorTests
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models/Chat/EmojiOnlyDetector.swift FlipcashCore/Tests/FlipcashCoreTests/EmojiOnlyDetectorTests.swift && git commit -m "feat(chat): detect a body that is nothing but one to three emoji"
```

---

### Task 2: `ChatMessage` carries the bubble run separately

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessage.swift:33-37`, `:65-91`, `:94-122`
- Test: `FlipcashCore/Tests/FlipcashCoreTests/ChatMessageRenderingTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `FlipcashCore/Tests/FlipcashCoreTests/ChatMessageRenderingTests.swift`:

```swift
//
//  ChatMessageRenderingTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("ChatMessage bare-emoji rendering")
struct ChatMessageRenderingTests {

    private func message(
        text: String = "👍",
        isEmojiOnly: Bool = true,
        linkPreview: LinkPreview? = nil,
        quote: ChatQuote? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: "1",
            text: text,
            sender: .me,
            isEmojiOnly: isEmojiOnly,
            linkPreview: linkPreview,
            quote: quote
        )
    }

    @Test("An emoji-only text row renders bare")
    func emojiOnlyTextRendersBare() {
        #expect(message().rendersAsLargeEmoji)
    }

    @Test("A row the mapper did not flag renders as a bubble")
    func unflaggedRowKeepsBubble() {
        #expect(!message(text: "hello", isEmojiOnly: false).rendersAsLargeEmoji)
    }

    @Test("A reply keeps its bubble — the quote panel lives inside it")
    func replyKeepsBubble() {
        let quote = ChatQuote(stableID: "0", authorName: "Them", snippet: "hi", kind: .text)
        #expect(!message(quote: quote).rendersAsLargeEmoji)
    }

    @Test("A link row keeps its bubble")
    func linkRowKeepsBubble() {
        let preview = LinkPreview(url: URL(string: "https://example.com")!)
        #expect(!message(linkPreview: preview).rendersAsLargeEmoji)
    }

    @Test("Cash and tombstone rows never render bare")
    func nonTextContentKeepsItsChrome() {
        let cash = ChatMessage(
            id: "1",
            content: .cash(ChatCashContent(amount: "$1.00", token: "Cash")),
            sender: .me,
            isEmojiOnly: true
        )
        let deleted = ChatMessage(
            id: "2",
            content: .deleted("This message was deleted"),
            sender: .me,
            isEmojiOnly: true
        )
        #expect(!cash.rendersAsLargeEmoji)
        #expect(!deleted.rendersAsLargeEmoji)
    }

    @Test("The bubble run defaults off and is independent of the author run")
    func bubbleRunIsItsOwnPair() {
        let row = ChatMessage(
            id: "1",
            text: "hi",
            sender: .me,
            isContinuationFromPrevious: true,
            isContinuedByNext: true
        )
        #expect(!row.joinsBubbleAbove)
        #expect(!row.joinsBubbleBelow)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./Scripts/test.sh FlipcashCoreTests/ChatMessageRenderingTests
```

Expected: compile failure — `extra argument 'isEmojiOnly' in call` and `value of type 'ChatMessage' has no member 'rendersAsLargeEmoji'`.

- [ ] **Step 3: Add the properties**

In `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessage.swift`, replace lines 33-37:

```swift
    /// The row above is the same sender — tighten the spacing and flatten the inner top
    /// corner so a same-sender run reads as one column.
    public let isContinuationFromPrevious: Bool
    /// The row below is the same sender — flatten the inner bottom corner.
    public let isContinuedByNext: Bool
```

with:

```swift
    /// The row above has the same author — the name above this row is suppressed, so a run reads as
    /// one speaker. Attribution only: the inner corner and the row gap are `joinsBubbleAbove`'s job.
    public let isContinuationFromPrevious: Bool
    /// The row below has the same author — the run's single gutter face sits on the row that closes
    /// it, not on this one. Attribution only, as above.
    public let isContinuedByNext: Bool
    /// The bubble above is part of the same *bubble* run: flatten the inner top corner. Separate
    /// from the author run because a bare emoji row breaks the chrome without breaking attribution.
    public let joinsBubbleAbove: Bool
    /// The bubble below is part of the same bubble run: flatten the inner bottom corner, and take
    /// the tight row gap.
    public let joinsBubbleBelow: Bool
    /// The body is one to three emoji and nothing else. Derived from the text at map time the way
    /// `linkPreview` is. `rendersAsLargeEmoji` is what decides the rendering — this flag is just the
    /// body test, so a reply or a link row can carry it and still draw a bubble.
    public let isEmojiOnly: Bool
```

Then, after the `isAttributedTranscript` declaration (currently line 63), add:

```swift
    /// Whether this row draws as bare, enlarged emoji instead of a bubble: an emoji-only text body
    /// with nothing else in the bubble to hold. A reply's quote panel and a link row's preview both
    /// live inside the bubble and have no standalone layout, so either one keeps the chrome.
    public var rendersAsLargeEmoji: Bool {
        guard isEmojiOnly, quote == nil, linkPreview == nil else { return false }
        switch content {
        case .text:           return true
        case .cash, .deleted: return false
        }
    }
```

- [ ] **Step 4: Thread the three parameters through both inits**

In the full init (currently line 65), add the three parameters immediately after `isContinuedByNext`:

```swift
    public init(
        id: String,
        content: Content,
        sender: Sender,
        isContinuationFromPrevious: Bool = false,
        isContinuedByNext: Bool = false,
        joinsBubbleAbove: Bool = false,
        joinsBubbleBelow: Bool = false,
        isEmojiOnly: Bool = false,
        receipt: ChatReceipt? = nil,
        linkPreview: LinkPreview? = nil,
        isEdited: Bool = false,
        actions: [MessageCapability] = [],
        quote: ChatQuote? = nil,
        author: ChatAuthor? = nil,
        isAttributedTranscript: Bool = false
    ) {
        self.id = id
        self.content = content
        self.sender = sender
        self.isContinuationFromPrevious = isContinuationFromPrevious
        self.isContinuedByNext = isContinuedByNext
        self.joinsBubbleAbove = joinsBubbleAbove
        self.joinsBubbleBelow = joinsBubbleBelow
        self.isEmojiOnly = isEmojiOnly
        self.receipt = receipt
        self.linkPreview = linkPreview
        self.isEdited = isEdited
        self.actions = actions
        self.quote = quote
        self.author = author
        self.isAttributedTranscript = isAttributedTranscript
    }
```

And the same three in the `text:` convenience init (currently line 94), forwarded in order:

```swift
    /// Convenience for text rows.
    public init(
        id: String,
        text: String,
        sender: Sender,
        isContinuationFromPrevious: Bool = false,
        isContinuedByNext: Bool = false,
        joinsBubbleAbove: Bool = false,
        joinsBubbleBelow: Bool = false,
        isEmojiOnly: Bool = false,
        receipt: ChatReceipt? = nil,
        linkPreview: LinkPreview? = nil,
        isEdited: Bool = false,
        actions: [MessageCapability] = [],
        quote: ChatQuote? = nil,
        author: ChatAuthor? = nil,
        isAttributedTranscript: Bool = false
    ) {
        self.init(
            id: id,
            content: .text(text),
            sender: sender,
            isContinuationFromPrevious: isContinuationFromPrevious,
            isContinuedByNext: isContinuedByNext,
            joinsBubbleAbove: joinsBubbleAbove,
            joinsBubbleBelow: joinsBubbleBelow,
            isEmojiOnly: isEmojiOnly,
            receipt: receipt,
            linkPreview: linkPreview,
            isEdited: isEdited,
            actions: actions,
            quote: quote,
            author: author,
            isAttributedTranscript: isAttributedTranscript
        )
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashCoreTests/ChatMessageRenderingTests
```

Expected: PASS, 6 tests.

- [ ] **Step 6: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessage.swift FlipcashCore/Tests/FlipcashCoreTests/ChatMessageRenderingTests.swift && git commit -m "feat(chat): split the bubble run from the author run on ChatMessage"
```

---

### Task 3: The mapper decides which rows render bare

**Files:**
- Modify: `Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift:86-89`, `:112-117`, `:176-194`
- Test: `FlipcashTests/Chat/ChatMessageMappingTests.swift`

- [ ] **Step 1: Write the failing tests**

In `FlipcashTests/Chat/ChatMessageMappingTests.swift`, add this helper next to the existing `text(_:_:_:after:)` (line 24):

```swift
    private func reply(_ id: UInt64, _ sender: UUID, _ body: String, to repliedTo: UInt64, after offset: TimeInterval) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .text(body),
            date: base.addingTimeInterval(offset),
            unreadSeq: id,
            repliedTo: MessageID(value: repliedTo)
        )
    }
```

and append these tests to the suite:

```swift
    @Test("A bare emoji row breaks the bubble run on both sides and leaves attribution alone")
    func emojiRowSplitsBubbleRunFromAuthorRun() {
        let items = ChatItem.from([
            text(1, them, "hello", after: 0),
            text(2, them, "👍", after: 60),
            text(3, them, "there", after: 120),
        ], selfUserID: me)
        let rows = messageRows(items)

        // The author run is untouched — one run of three from the same sender.
        #expect(rows.map(\.isContinuationFromPrevious) == [false, true, true])
        #expect(rows.map(\.isContinuedByNext) == [true, true, false])

        // The bubble run is broken around the emoji row, on the row itself and on both neighbours.
        #expect(rows.map(\.joinsBubbleAbove) == [false, false, false])
        #expect(rows.map(\.joinsBubbleBelow) == [false, false, false])

        #expect(rows.map(\.isEmojiOnly) == [false, true, false])
        #expect(rows.map(\.rendersAsLargeEmoji) == [false, true, false])
    }

    @Test("Two adjacent bubbles still join")
    func bubbleRunSurvivesWithoutAnEmojiRow() {
        let items = ChatItem.from([text(1, me, "a", after: 0), text(2, me, "b", after: 60)], selfUserID: me)
        let rows = messageRows(items)
        #expect(rows[0].joinsBubbleBelow)
        #expect(rows[1].joinsBubbleAbove)
    }

    @Test("An emoji reply keeps its bubble and its place in the bubble run")
    func emojiReplyKeepsBubble() {
        let items = ChatItem.from([
            text(1, them, "hello", after: 0),
            reply(2, them, "👍", to: 1, after: 60),
        ], selfUserID: me)
        let rows = messageRows(items)

        #expect(rows[1].isEmojiOnly)
        #expect(!rows[1].rendersAsLargeEmoji)
        #expect(rows[0].joinsBubbleBelow)
        #expect(rows[1].joinsBubbleAbove)
    }

    @Test("A cash row is never emoji-only")
    func cashRowIsNeverEmojiOnly() {
        let items = ChatItem.from([text(1, me, "👍", after: 0)], selfUserID: me)
        #expect(messageRows(items)[0].isEmojiOnly)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./Scripts/test.sh FlipcashTests/ChatMessageMappingTests
```

Expected: FAIL — `rows.map(\.joinsBubbleAbove)` is all-`false` by default so the emoji assertions pass vacuously, but `bubbleRunSurvivesWithoutAnEmojiRow` fails (`Expectation failed: rows[0].joinsBubbleBelow`) and `isEmojiOnly` is `false` everywhere.

- [ ] **Step 3: Compute the flags in the mapper**

In `Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift`, after the `separates(_:from:)` function (ending line 89), add:

```swift
        // What renders bare: a text body of one to three emoji, on a row that is not a reply — the
        // quote panel lives inside the bubble and has no standalone layout. One predicate, applied to
        // the row and to both neighbours, so a single place decides what counts.
        func isEmojiOnlyBody(_ message: ConversationMessage) -> Bool {
            switch message.content {
            case .text(let text): EmojiOnlyDetector.isEmojiOnly(text)
            case .cash, .deleted: false
            }
        }
        func rendersBare(_ message: ConversationMessage) -> Bool {
            message.repliedTo == nil && isEmojiOnlyBody(message)
        }
```

Then, immediately after the `groupedBelow` binding (ending line 117), add:

```swift
            // The bubble run, which is not the author run. A bubble stacked above a bare emoji would
            // otherwise flatten its inner corner from 12 to 4 and take the 5pt gap, pointing at a
            // bubble that is not there — while the name and the gutter face stay where they are.
            let isBare = rendersBare(message)
            let joinsBubbleAbove = groupedAbove && !isBare && !(previous.map(rendersBare) ?? false)
            let joinsBubbleBelow = groupedBelow && !isBare && !(next.map(rendersBare) ?? false)
```

And in the `ChatMessage` construction (line 176), insert the three arguments after `isContinuedByNext`:

```swift
            items.append(.message(ChatMessage(
                id: message.stableID,
                content: content,
                sender: isFromSelf ? .me : .other,
                isContinuationFromPrevious: groupedAbove,
                isContinuedByNext: groupedBelow,
                joinsBubbleAbove: joinsBubbleAbove,
                joinsBubbleBelow: joinsBubbleBelow,
                isEmojiOnly: isEmojiOnlyBody(message),
                receipt: receipt,
```

(The rest of the call — `linkPreview:` through `isAttributedTranscript:` — is unchanged.)

- [ ] **Step 4: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashTests/ChatMessageMappingTests
```

Expected: PASS — the whole suite, including the pre-existing grouping tests.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift FlipcashTests/Chat/ChatMessageMappingTests.swift && git commit -m "feat(chat): break the bubble run around an emoji-only row"
```

---

### Task 4: Corners and row gap read the bubble run

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatBubbleView.swift:135-136`, `:197-198`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/LinkableBubbleView.swift:156-157`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatCashCardCell.swift:143-144`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift:727`, `:975-981`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatScrollBenchmark.swift:270-279`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatMotionSandbox.swift:205-213`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatMessageCell.swift:66-67`
- Test: `FlipcashTests/Chat/ChatViewControllerTests.swift:237-248`, `FlipcashTests/Chat/ChatChangesetFlatteningTests.swift:21-36`

- [ ] **Step 1: Write the failing test**

In `FlipcashTests/Chat/ChatViewControllerTests.swift`, replace the `message(_:_:continuedByNext:)` helper (line 237) with one that sets both runs, so the existing spacing tests keep their meaning:

```swift
    private func message(
        _ id: String,
        _ sender: ChatMessage.Sender,
        continuedByNext: Bool = false
    ) -> ChatItem {
        .message(ChatMessage(
            id: id,
            content: .text("hi"),
            sender: sender,
            isContinuedByNext: continuedByNext,
            joinsBubbleBelow: continuedByNext
        ))
    }
```

and add:

```swift
    @Test("A bare emoji row below a bubble takes the normal gap, not the run's tight one")
    func emojiRowBreaksTheTightGap() {
        let items: [ChatItem] = [
            .message(ChatMessage(id: "1", text: "hi", sender: .me, isContinuedByNext: true)),
            .message(ChatMessage(id: "2", text: "👍", sender: .me, isContinuationFromPrevious: true, isEmojiOnly: true)),
        ]
        #expect(gap(after: 0, in: items) == 10)
    }
```

- [ ] **Step 2: Run the tests to verify the new one fails**

```bash
./Scripts/test.sh FlipcashTests/ChatViewControllerTests
```

Expected: FAIL on `emojiRowBreaksTheTightGap` — `Expectation failed: gap(after: 0, in: items) == 10` (it is 5, because the spacing still reads `isContinuedByNext`).

- [ ] **Step 3: Swap the three radii call sites**

`ChatBubbleView.swift:132-138` becomes:

```swift
        background.apply(
            fill: BubbleBackgroundView.fill(isFromSelf: message.sender == .me),
            radii: BubbleBackgroundView.radii(
                isFromSelf: message.sender == .me,
                groupedAbove: message.joinsBubbleAbove,
                groupedBelow: message.joinsBubbleBelow
            ),
            identity: message.id
        )
```

Make the identical substitution at `LinkableBubbleView.swift:156-157` and `ChatCashCardCell.swift:143-144`:

```swift
                groupedAbove: message.joinsBubbleAbove,
                groupedBelow: message.joinsBubbleBelow
```

- [ ] **Step 4: Swap the row gap**

`ChatViewController.swift:727` becomes:

```swift
        return message(at: indexPath)?.joinsBubbleBelow == true ? RowGap.tight : nil
```

- [ ] **Step 5: Mirror the flags at every synthetic call site**

`ChatViewController.swift:975-981` (`previewConversation`):

```swift
        return (0..<count).map { (i: Int) -> ChatMessage in
            let isContinuation = i > 0 && senders[i - 1] == senders[i]
            let isContinued = i < count - 1 && senders[i + 1] == senders[i]
            return ChatMessage(
                id: "msg-\(i)",
                text: texts[i % texts.count],
                sender: senders[i],
                isContinuationFromPrevious: isContinuation,
                isContinuedByNext: isContinued,
                joinsBubbleAbove: isContinuation,
                joinsBubbleBelow: isContinued
            )
        }
```

`ChatScrollBenchmark.swift:272-279`:

```swift
            items.append(.message(ChatMessage(
                id: "bench-\(index)",
                text: texts[index % texts.count],
                sender: sender,
                isContinuationFromPrevious: isContinuation,
                isContinuedByNext: isContinued,
                joinsBubbleAbove: isContinuation,
                joinsBubbleBelow: isContinued,
                author: sender == .me ? nil : author,
                isAttributedTranscript: !authors.isEmpty
            )))
```

`ChatMotionSandbox.swift:204-215` (`grouped(_:)` — the sandbox re-derives both runs so the corner morph has something to animate):

```swift
    private static func grouped(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.enumerated().map { index, message in
            let above = index > 0 && messages[index - 1].sender == message.sender
            let below = index < messages.count - 1 && messages[index + 1].sender == message.sender
            return ChatMessage(
                id: message.id,
                content: message.content,
                sender: message.sender,
                isContinuationFromPrevious: above,
                isContinuedByNext: below,
                joinsBubbleAbove: above,
                joinsBubbleBelow: below,
                receipt: message.receipt,
                linkPreview: message.linkPreview
            )
        }
    }
```

`ChatMessageCell.swift:66-67` (`#Preview`):

```swift
        ChatMessage(id: "2", text: "And a reply from me.", sender: .me, isContinuedByNext: true, joinsBubbleBelow: true),
        ChatMessage(id: "3", text: "Second line, same sender, so the corner flattens.", sender: .me, isContinuationFromPrevious: true, joinsBubbleAbove: true),
```

`ChatBubbleView.swift:197-198` (`#Preview`):

```swift
        ChatMessage(id: "2", text: "Pretty good.", sender: .me, isContinuedByNext: true, joinsBubbleBelow: true),
        ChatMessage(id: "3", text: "This one is much longer to show the bubble wrap across several lines and hug its content nicely.", sender: .me, isContinuationFromPrevious: true, joinsBubbleAbove: true),
```

`ChatChangesetFlatteningTests.swift:21-36` — the flattening tests are about a run's corners changing, so the helper sets both pairs:

```swift
    private func message(
        _ id: String,
        sender: ChatMessage.Sender = .me,
        continuedByNext: Bool = false,
        continuationFromPrevious: Bool = false,
        receipt: ChatReceipt? = nil
    ) -> ChatItem {
        .message(ChatMessage(
            id: id,
            text: "text-\(id)",
            sender: sender,
            isContinuationFromPrevious: continuationFromPrevious,
            isContinuedByNext: continuedByNext,
            joinsBubbleAbove: continuationFromPrevious,
            joinsBubbleBelow: continuedByNext,
            receipt: receipt
        ))
    }
```

`ChatTranscriptDiffFuzzTests.swift:56-63` — the generator's `grouped` bit drives the corner, so it sets both:

```swift
            case .text(let id, let receipt, let grouped):
                .message(ChatMessage(
                    id: "m\(id)",
                    text: "text-\(id)",
                    sender: id.isMultiple(of: 2) ? .me : .other,
                    isContinuationFromPrevious: grouped,
                    joinsBubbleAbove: grouped,
                    receipt: receipt ? .read(time: nil) : nil
                ))
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashTests/ChatViewControllerTests
```

Expected: PASS, including `emojiRowBreaksTheTightGap`.

```bash
./Scripts/test.sh FlipcashTests/ChatChangesetFlatteningTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "refactor(chat): draw corners and row gaps from the bubble run"
```

---

### Task 5: The attention flash moves to `ChatMotion`

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatMotion.swift:153-160`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/BubbleBackgroundView.swift:113-138`, `:159-170`

No new test: this is a pure extraction, covered by the existing quote-jump tests that assert `isFlashingAttention`.

- [ ] **Step 1: Add the builder to `ChatMotion`**

In `FlipcashUI/Sources/FlipcashUI/Chat/ChatMotion.swift`, after `attentionDuration` (line 160), add:

```swift
    /// The quote-jump flash: a keyframe on `opacity` that lights quickly, holds, then fades slowly,
    /// leaving the resting value at 0 throughout. Built here rather than in a view because two
    /// different grounds play it — a bubble's wash layer and a bare emoji row's own patch — and they
    /// must run to one timing.
    ///
    /// `start` is when the flash began, on `CACurrentMediaTime()`'s clock. A time already past joins
    /// a flash in progress rather than restarting it, so a row re-dequeued mid-flash picks it up
    /// where it left off and still ends when it would have.
    nonisolated public static func attentionFlash(startedAt start: CFTimeInterval) -> CAKeyframeAnimation {
        let total = attentionDuration
        let flash = CAKeyframeAnimation(keyPath: "opacity")
        flash.values = [0, 1, 1, 0]
        flash.keyTimes = [
            0,
            NSNumber(value: attentionRise / total),
            NSNumber(value: (attentionRise + attentionHold) / total),
            1,
        ]
        flash.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        flash.duration = total
        flash.beginTime = start
        return flash
    }
```

- [ ] **Step 2: Call it from `BubbleBackgroundView`**

Replace `BubbleBackgroundView.swift:113-138` with:

```swift
    /// Brightens the bubble's ground for `ChatMotion.attentionDuration`, then lets it fade back.
    ///
    /// Runs as a keyframe on the layer rather than a `UIView` animation because the resting opacity
    /// must stay 0 throughout: the row can be reconfigured or recycled mid-flash, and a model value
    /// left raised would strand a lit bubble.
    func flashAttention(startedAt start: CFTimeInterval = CACurrentMediaTime()) {
        attentionLayer.removeAnimation(forKey: Self.attentionKey)
        attentionLayer.add(ChatMotion.attentionFlash(startedAt: start), forKey: Self.attentionKey)
    }
```

- [ ] **Step 3: Make `raise` a no-op without a shape**

Replace `BubbleBackgroundView.swift:164-170` with:

```swift
    static func raise(_ view: UIView, shape: UIBezierPath?) {
        // No path means no bubble to trace, and Core Animation would fall back to the layer tree's
        // alpha channel — behind a bare emoji row that is a dark blob around the glyphs rather than
        // an edge. A shapeless caller gets no lift at all.
        guard let shape else { return lower(view) }
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = liftShadowOpacity
        view.layer.shadowRadius = liftShadowRadius
        view.layer.shadowOffset = liftShadowOffset
        view.layer.shadowPath = shape.cgPath
    }
```

- [ ] **Step 4: Run the suites that cover the flash and the lift**

```bash
./Scripts/test.sh FlipcashTests/ChatMotionTests && ./Scripts/test.sh FlipcashTests/ChatViewControllerTests && ./Scripts/test.sh FlipcashTests/ChatBubbleViewTests
```

Expected: PASS. `ChatViewControllerTests` is the one that exercises `flashAttention` through `BubbleCarrying`.

- [ ] **Step 5: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatMotion.swift FlipcashUI/Sources/FlipcashUI/Chat/BubbleBackgroundView.swift && git commit -m "refactor(chat): move the attention keyframe into ChatMotion"
```

---

### Task 6: `LargeEmojiView`

**Files:**
- Create: `FlipcashUI/Sources/FlipcashUI/Chat/LargeEmojiView.swift`

The cell tests in Task 8 cover this view; it has no behaviour worth testing without a cell around it.

- [ ] **Step 1: Write the view**

Create `FlipcashUI/Sources/FlipcashUI/Chat/LargeEmojiView.swift`:

```swift
//
//  LargeEmojiView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// A message body that is nothing but one to three emoji, drawn bare and enlarged — no bubble, no
/// border, no wash. The column around it supplies the row's side, its gutter and its metadata line;
/// this view is only the glyphs and the ground the quote-jump flash lights.
///
/// It deliberately does not reuse `BubbleBackgroundView`. That view composites its wash over an
/// opaque base, on purpose, so a bubble renders the same under the context menu's dim and the edit
/// blur. Behind a bare emoji the same opaque base would show as a rectangular patch against both.
final class LargeEmojiView: UIView {

    /// The bare emoji's type size — one size for one, two or three of them.
    static let fontSize: CGFloat = 48

    /// Keeps the glyphs off the rows above and below, in place of a bubble's inset.
    private static let verticalPadding: CGFloat = 4
    private static let attentionKey = "attention"
    /// The same lift the bubble's ground takes, so a jumped-to emoji reads as the same event.
    private static let attentionWash = UIColor.white.withAlphaComponent(0.10)
    private static let attentionRadius: CGFloat = 12
    /// How far the lit patch spreads past the glyphs, so the flash reads as a highlight rather than
    /// a box drawn tight around them.
    private static let attentionSpread: CGFloat = 6

    private let label = UILabel()
    private let attentionLayer = CALayer()
    /// The row this view currently draws, so a recycled view drops a flash meant for another one.
    private var identity: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: Self.fontSize)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        attentionLayer.backgroundColor = Self.attentionWash.cgColor
        attentionLayer.cornerRadius = Self.attentionRadius
        attentionLayer.cornerCurve = .continuous
        attentionLayer.opacity = 0
        // Resized in `layoutSubviews`, where an implicit animation would drag the patch behind the
        // row's own frame change.
        attentionLayer.actions = ["position": NSNull(), "bounds": NSNull()]
        layer.addSublayer(attentionLayer)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        attentionLayer.frame = bounds.insetBy(dx: -Self.attentionSpread, dy: -Self.attentionSpread)
    }

    /// Draws `message`'s body. A non-text row never reaches here — `rendersAsLargeEmoji` is false for
    /// one — so the guard is the switch's exhaustive form rather than a fallback.
    func configure(with message: ChatMessage) {
        if identity != message.id {
            attentionLayer.removeAnimation(forKey: Self.attentionKey)
        }
        identity = message.id
        switch message.content {
        case .text(let text):     label.text = text
        case .cash, .deleted:     label.text = nil
        }
    }

    /// Clears the glyphs and cancels any flash in flight. Call from `prepareForReuse`.
    func reset() {
        attentionLayer.removeAnimation(forKey: Self.attentionKey)
        label.text = nil
        identity = nil
    }

    /// Lights the ground behind the glyphs, on `ChatMotion`'s shared timing.
    func flashAttention(startedAt start: CFTimeInterval = CACurrentMediaTime()) {
        attentionLayer.removeAnimation(forKey: Self.attentionKey)
        attentionLayer.add(ChatMotion.attentionFlash(startedAt: start), forKey: Self.attentionKey)
    }

    /// Whether a flash is currently running — the test hook, matching `BubbleBackgroundView`'s.
    var isFlashingAttention: Bool { attentionLayer.animation(forKey: Self.attentionKey) != nil }
}
#endif
```

- [ ] **Step 2: Build to verify it compiles**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/LargeEmojiView.swift && git commit -m "feat(chat): add the bare, enlarged emoji body view"
```

---

### Task 7: The column's bottom slot becomes a metadata row

This is the riskiest edit in the plan: it moves a view whose implicit-animation suppression is load-bearing and shared by every cell in the transcript.

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatReceiptView.swift:20-26`, `:186-189`, `:224`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatColumnCell.swift:26`, `:61-108`, `:156-175`, `:180-193`, `:240-248`

- [ ] **Step 1: Promote `trailingPadding` onto `ChatReceiptView`**

In `ChatReceiptView.swift`, after `failedColor` (line 25), add:

```swift
    /// Keeps the line off the column's trailing edge. Owned by the view rather than the face because
    /// the metadata row applies the same inset when the receipt is hidden and "Edited" stands alone —
    /// otherwise a lone marker sits 10pt further out than "Delivered" did.
    static let trailingPadding: CGFloat = 10
```

Delete `ChatReceiptFace`'s own copy (line 188):

```swift
    /// Keeps the line off the column's trailing edge.
    private static let trailingPadding: CGFloat = 10
```

and point its constraint (line 224) at the promoted constant:

```swift
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ChatReceiptView.trailingPadding),
```

- [ ] **Step 2: Add the metadata row to `ChatColumnCell`**

In `ChatColumnCell.swift`, replace line 26 with:

```swift
    private let receipt = ChatReceiptView()
    /// The "Edited" marker on the metadata line, for a row that has no bubble to put it in. Hidden
    /// on every other cell, which draws the marker inside the bubble as it always has.
    private let editedMarker = EditedMarker.makeLabel()
    private let metadata = ChatMetadataRow()
```

In `installColumn(content:)`, replace line 72 (`column.addArrangedSubview(receipt)`) with:

```swift
        metadata.axis = .horizontal
        // The two pieces are set in the same 11pt type, so centring them reads as one line without
        // asking a stack for a baseline that `ChatReceiptView` — a plain view around two faces — does
        // not vend.
        metadata.alignment = .center
        metadata.spacing = Self.metadataSpacing
        metadata.isLayoutMarginsRelativeArrangement = true
        metadata.directionalLayoutMargins = .zero
        editedMarker.isHidden = true
        metadata.addArrangedSubview(editedMarker)
        metadata.addArrangedSubview(receipt)
        metadata.isHidden = true
        column.addArrangedSubview(metadata)
```

Next to `rowInset` (line 111), add:

```swift
    /// Between "Edited" and the receipt — the same gap the receipt sets between its own two halves.
    private static let metadataSpacing: CGFloat = 4
```

- [ ] **Step 3: Reset and update it**

In `prepareForReuse`, after `receipt.reset()` (line 166), add:

```swift
        editedMarker.isHidden = true
        metadata.isHidden = true
```

In `updateColumn`, change the signature and the receipt block (lines 180-193):

```swift
    /// Sets the status line and hugs the column to the sender's edge. Call from `configure`. The line
    /// itself comes from the mapping (`message.receipt`) and renders itself; the cell only decides
    /// whether the update animates, and makes a failed row tappable to retry.
    ///
    /// - Parameter showsEditedMarker: draws "Edited" on the metadata line, to the left of the
    ///   receipt. Only a row with no bubble asks for this; every other cell draws the marker inside
    ///   its bubble.
    func updateColumn(for message: ChatMessage, authorImageData: Data? = nil, showsEditedMarker: Bool = false) {
        let isInPlaceUpdate = currentMessageID == message.id
        currentMessageID = message.id
        retryID = message.isFailed ? message.id : nil
        retryTap?.isEnabled = message.isFailed
        receipt.setReceipt(message.receipt, animated: isInPlaceUpdate && window != nil)
        editedMarker.isHidden = !showsEditedMarker
        // Collapsed when it holds neither piece, or the column's 4pt spacing leaves a gap under every
        // row that carries no metadata at all.
        metadata.isHidden = editedMarker.isHidden && receipt.isHidden
        // The receipt carries its own trailing padding inside its faces; a marker standing alone has
        // none, and would sit 10pt further out than the line it replaces.
        metadata.directionalLayoutMargins.trailing = receipt.isHidden ? ChatReceiptView.trailingPadding : 0
        column.alignment = message.sender == .me ? .trailing : .leading
        updateAttribution(for: message, authorImageData: authorImageData)
    }
```

(The three comment lines above `let isInPlaceUpdate` at 181-184 stay as they are.)

- [ ] **Step 4: Keep retry's hit area on the row the user sees**

Replace line 246:

```swift
        return (content.map { $0.frame.contains(point) } ?? false) || (!metadata.isHidden && metadata.frame.contains(point))
```

- [ ] **Step 5: Add the row's own class**

At the end of `ChatColumnCell.swift`, before the closing `#endif`, add:

```swift
/// The line under a row's content: an optional "Edited" marker and the receipt, trailing-aligned so
/// the two read as one piece of metadata.
///
/// A subclass only so it can refuse the implicit geometry animation, for the same reason
/// `ChatReceiptView` does: an arranged subview revealed inside a batch update otherwise springs in
/// from the stack's origin, and nesting the receipt a level deeper would let showing or hiding
/// "Edited" drag the Delivered→Read swap sideways. `transform` and `opacity` still fall through, so
/// the faces animate as they always did.
private final class ChatMetadataRow: UIStackView {

    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        if layer === self.layer, event == "position" || event == "bounds" {
            return NSNull()
        }
        return super.action(for: layer, forKey: event)
    }
}
```

- [ ] **Step 6: Run the receipt and cell suites**

```bash
./Scripts/test.sh FlipcashTests/ChatReceiptViewTests && ./Scripts/test.sh FlipcashTests/ChatReceiptTests && ./Scripts/test.sh FlipcashTests/ChatLinkMessageCellTests
```

Expected: PASS. `ChatReceiptViewTests` is the one that guards the reveal and the Delivered→Read swap — the behaviour this task puts a stack level above.

- [ ] **Step 7: Check the receipt by eye on an ordinary text row**

Build and run, send a message, and watch the "Delivered" reveal and the Delivered→Read swap on a *text* row — the animation this task moved is shared by every cell, and an emoji row is not where a regression would show first.

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatColumnCell.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatReceiptView.swift && git commit -m "feat(chat): give a chat row a metadata line for Edited and the receipt"
```

---

### Task 8: `ChatEmojiMessageCell`

**Files:**
- Create: `FlipcashUI/Sources/FlipcashUI/Chat/ChatEmojiMessageCell.swift`
- Test: `FlipcashTests/Chat/ChatEmojiMessageCellTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `FlipcashTests/Chat/ChatEmojiMessageCellTests.swift`:

```swift
//
//  ChatEmojiMessageCellTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatEmojiMessageCell")
struct ChatEmojiMessageCellTests {

    private func makeCell() -> ChatEmojiMessageCell {
        ChatEmojiMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
    }

    private func message(_ body: String = "👍", isEdited: Bool = false, receipt: ChatReceipt? = nil) -> ChatMessage {
        ChatMessage(id: "1", text: body, sender: .me, isEmojiOnly: true, receipt: receipt, isEdited: isEdited)
    }

    @Test("The row draws no bubble chrome")
    func noBubbleChrome() {
        let cell = makeCell()
        cell.configure(with: message(), maxWidth: 280)
        cell.layoutIfNeeded()
        #expect(cell.descendants(of: BubbleBackgroundView.self).isEmpty)
    }

    @Test("The emoji is drawn at the large size")
    func emojiIsLarge() {
        let cell = makeCell()
        cell.configure(with: message(), maxWidth: 280)
        cell.layoutIfNeeded()
        let label = cell.descendants(of: UILabel.self).first { $0.text == "👍" }
        #expect(label?.font.pointSize == LargeEmojiView.fontSize)
    }

    @Test("Edited lands on the metadata line, outside the body")
    func editedMarkerIsOnTheMetadataLine() {
        let cell = makeCell()
        cell.configure(with: message(isEdited: true), maxWidth: 280)
        cell.layoutIfNeeded()

        let marker = cell.descendants(of: UILabel.self).first { $0.text == EditedMarker.text }
        #expect(marker != nil)
        #expect(marker?.isHidden == false)

        // It belongs to the column, not to the emoji body.
        let body = cell.descendants(of: LargeEmojiView.self).first
        let markersInBody = body?.descendants(of: UILabel.self).filter { $0.text == EditedMarker.text } ?? []
        #expect(markersInBody.isEmpty)
    }

    @Test("An unedited row draws no marker")
    func noMarkerWhenUnedited() {
        let cell = makeCell()
        cell.configure(with: message(), maxWidth: 280)
        cell.layoutIfNeeded()
        let marker = cell.descendants(of: UILabel.self).first { $0.text == EditedMarker.text }
        #expect(marker?.isHidden ?? true)
    }

    @Test("Edited sits beside the receipt rather than replacing it")
    func editedAndReceiptShareTheLine() {
        let cell = makeCell()
        cell.configure(with: message(isEdited: true, receipt: .delivered), maxWidth: 280)
        cell.layoutIfNeeded()

        let labels = cell.descendants(of: UILabel.self)
        #expect(labels.contains { $0.text == EditedMarker.text && !$0.isHidden })
        #expect(labels.contains { $0.text == "Delivered" })
    }

    @Test("The quote-jump flash runs on the row's own ground")
    func flashRunsWithoutABubble() {
        let cell = makeCell()
        cell.configure(with: message(), maxWidth: 280)
        cell.layoutIfNeeded()
        cell.flashAttention(startedAt: CACurrentMediaTime())
        #expect(cell.descendants(of: LargeEmojiView.self).first?.isFlashingAttention == true)
    }

    @Test("The lift preview is the emoji itself, with no bubble shape to clip to")
    func liftPreviewIsTheEmoji() {
        let cell = makeCell()
        cell.configure(with: message(), maxWidth: 280)
        #expect(cell.liftPreviewView is LargeEmojiView)
        #expect(cell.liftPreviewMaskingPath == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./Scripts/test.sh FlipcashTests/ChatEmojiMessageCellTests
```

Expected: compile failure — `cannot find 'ChatEmojiMessageCell' in scope`.

- [ ] **Step 3: Write the cell**

Create `FlipcashUI/Sources/FlipcashUI/Chat/ChatEmojiMessageCell.swift`:

```swift
//
//  ChatEmojiMessageCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// A recycled cell for a message whose whole body is one to three emoji: the glyphs alone, bare and
/// enlarged, with no bubble around them. Subclassing `ChatColumnCell` carries the receipt line,
/// tap-to-retry, the avatar gutter and swipe-to-reply across unchanged; only the content view
/// differs.
public final class ChatEmojiMessageCell: ChatColumnCell {

    public static let reuseIdentifier = "ChatEmojiMessageCell"

    private let emoji = LargeEmojiView()
    private var maxWidthConstraint: NSLayoutConstraint!

    public override init(frame: CGRect) {
        super.init(frame: frame)
        installColumn(content: emoji)
        // Three 48pt emoji come nowhere near this; the cap is here so a detector bug cannot produce
        // an unbounded row.
        maxWidthConstraint = emoji.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        maxWidthConstraint.isActive = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameter maxWidth: the widest the body may grow, in points. The owner derives it from the
    ///   collection view's width, exactly as it does for a bubble.
    public func configure(with message: ChatMessage, maxWidth: CGFloat, authorImageData: Data? = nil) {
        emoji.configure(with: message)
        maxWidthConstraint.constant = maxWidth
        // There is no bubble to hold the marker, so it goes on the metadata line beside the receipt.
        updateColumn(for: message, authorImageData: authorImageData, showsEditedMarker: message.isEdited)
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        emoji.reset()
    }
}

extension ChatEmojiMessageCell: BubbleCarrying {
    var liftPreviewView: UIView { emoji }
    /// Nil on purpose: a bare emoji lifts as itself. There is no bubble shape to clip the preview to,
    /// and `BubbleBackgroundView.raise` takes that as "cast no shadow" rather than tracing one from
    /// the glyphs' alpha.
    var liftPreviewMaskingPath: UIBezierPath? { nil }
    func flashAttention(startedAt start: CFTimeInterval) { emoji.flashAttention(startedAt: start) }
}

#Preview("Bare emoji rows") {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false

    let samples: [ChatMessage] = [
        ChatMessage(id: "1", text: "👍", sender: .other, isEmojiOnly: true),
        ChatMessage(id: "2", text: "😀🎉", sender: .me, isEmojiOnly: true),
        ChatMessage(id: "3", text: "👨‍👩‍👧‍👦👍🏽🇺🇸", sender: .me, isEmojiOnly: true, receipt: .delivered, isEdited: true),
    ]
    for message in samples {
        let cell = ChatEmojiMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        cell.configure(with: message, maxWidth: 280)
        cell.widthAnchor.constraint(equalToConstant: 320).isActive = true
        stack.addArrangedSubview(cell)
    }

    let container = UIView()
    container.backgroundColor = UIColor(Color.backgroundMain)
    container.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])
    return container
}
#endif
```

The preview uses `Color.backgroundMain`, so add `import SwiftUI` beside `import UIKit`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashTests/ChatEmojiMessageCellTests
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatEmojiMessageCell.swift FlipcashTests/Chat/ChatEmojiMessageCellTests.swift && git commit -m "feat(chat): render an emoji-only message without a bubble"
```

---

### Task 9: The transcript picks the cell

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatItem+Differentiable.swift:26-48`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift:215-221`, `:405-419`
- Modify: `FlipcashTests/Chat/ChatTranscriptDiffFuzzTests.swift:37-50`, `:56-82`, `:107-113`
- Test: `FlipcashTests/Chat/ChatItemCellSelectionTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `FlipcashTests/Chat/ChatItemCellSelectionTests.swift`:

```swift
//
//  ChatItemCellSelectionTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import FlipcashUI

@Suite("ChatItem cell selection")
struct ChatItemCellSelectionTests {

    private func item(
        text: String = "👍",
        isEmojiOnly: Bool = true,
        linkPreview: LinkPreview? = nil,
        quote: ChatQuote? = nil
    ) -> ChatItem {
        .message(ChatMessage(
            id: "1",
            text: text,
            sender: .me,
            isEmojiOnly: isEmojiOnly,
            linkPreview: linkPreview,
            quote: quote
        ))
    }

    @Test("An emoji-only row picks the emoji cell")
    func emojiRowPicksTheEmojiCell() {
        #expect(item().cellReuseIdentifier == ChatEmojiMessageCell.reuseIdentifier)
    }

    @Test("A plain text row still picks the message cell")
    func textRowPicksTheMessageCell() {
        #expect(item(text: "hello", isEmojiOnly: false).cellReuseIdentifier == ChatMessageCell.reuseIdentifier)
    }

    @Test("An emoji reply keeps the bubble cell")
    func replyPicksTheMessageCell() {
        let quote = ChatQuote(stableID: "0", authorName: "Them", snippet: "hi", kind: .text)
        #expect(item(quote: quote).cellReuseIdentifier == ChatMessageCell.reuseIdentifier)
    }

    @Test("A link row keeps the link cell")
    func linkRowPicksTheLinkCell() {
        let preview = LinkPreview(url: URL(string: "https://example.com")!)
        #expect(item(linkPreview: preview).cellReuseIdentifier == ChatLinkMessageCell.reuseIdentifier)
    }

    @Test("A tombstone with an emoji body keeps the message cell")
    func tombstonePicksTheMessageCell() {
        let deleted = ChatItem.message(ChatMessage(
            id: "1",
            content: .deleted("This message was deleted"),
            sender: .me,
            isEmojiOnly: true
        ))
        #expect(deleted.cellReuseIdentifier == ChatMessageCell.reuseIdentifier)
    }

    @Test("Editing a row into emoji-only changes its difference identity")
    func classChangeChangesIdentity() {
        #expect(item(text: "hello", isEmojiOnly: false).differenceIdentifier != item().differenceIdentifier)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./Scripts/test.sh FlipcashTests/ChatItemCellSelectionTests
```

Expected: FAIL on `emojiRowPicksTheEmojiCell` and `classChangeChangesIdentity` — both still resolve to `ChatMessageCell`.

- [ ] **Step 3: Teach `cellReuseIdentifier` about the emoji cell**

Replace `ChatItem+Differentiable.swift:26-48` with:

```swift
    var cellReuseIdentifier: String {
        switch self {
        case .typingIndicator:
            ChatTypingIndicatorCell.reuseIdentifier
        case .profileCard:
            ChatProfileCardCell.reuseIdentifier
        case .groupCard:
            ChatGroupCardCell.reuseIdentifier
        case .dateSeparator:
            ChatDateSeparatorCell.reuseIdentifier
        case .message(let message):
            Self.messageCellReuseIdentifier(for: message)
        }
    }

    /// The cell class a message row renders with. A bare emoji row is its own class, so editing a
    /// message into or out of emoji-only diffs as delete+insert — the rule the transcript already
    /// applies to text ↔ cash and to a link gained or lost.
    private static func messageCellReuseIdentifier(for message: ChatMessage) -> String {
        if message.rendersAsLargeEmoji { return ChatEmojiMessageCell.reuseIdentifier }
        switch message.content {
        case .text:
            return message.linkPreview != nil ? ChatLinkMessageCell.reuseIdentifier : ChatMessageCell.reuseIdentifier
        case .deleted:
            // Deliberately the same cell class as plain text: a message becoming a tombstone
            // then diffs as an in-place reconfigure rather than a delete-and-insert.
            return ChatMessageCell.reuseIdentifier
        case .cash:
            return ChatCashCardCell.reuseIdentifier
        }
    }
```

- [ ] **Step 4: Register and configure the cell**

In `ChatViewController.swift`, after line 215, add:

```swift
        collectionView.register(ChatEmojiMessageCell.self, forCellWithReuseIdentifier: ChatEmojiMessageCell.reuseIdentifier)
```

and in `configure(_:with:)`, after the `ChatMessageCell` branch (line 416), add:

```swift
        case let cell as ChatEmojiMessageCell:
            cell.configure(with: message, maxWidth: maxWidth, authorImageData: authorImageData)
            cell.onRetry = { [weak self] id in self?.onRetry?(id) }
```

- [ ] **Step 5: Teach the fuzz generator to flip in and out of the emoji cell**

In `ChatTranscriptDiffFuzzTests.swift`, add the case to `Row` (line 41) and to `messageID`:

```swift
    private enum Row {
        case text(id: Int, receipt: Bool, grouped: Bool)
        case emoji(id: Int)
        case link(id: Int)
        case cash(id: Int)
        case separator(id: Int)
        case typing

        var messageID: Int? {
            switch self {
            case .text(let id, _, _), .emoji(let id), .link(let id), .cash(let id), .separator(let id): id
            case .typing: nil
            }
        }
    }
```

Add its arm to `build(_:)`, after the `.text` case:

```swift
            case .emoji(let id):
                .message(ChatMessage(
                    id: "m\(id)",
                    text: "👍",
                    sender: .me,
                    isEmojiOnly: true
                ))
```

and put it in the kind-flip (`case 6, 7`):

```swift
                switch rows[index] {
                case .text: rows[index] = Bool.random(using: &rng) ? .cash(id: id) : (Bool.random(using: &rng) ? .link(id: id) : .emoji(id: id))
                case .cash, .link, .emoji: rows[index] = .text(id: id, receipt: false, grouped: false)
                case .separator, .typing: break
                }
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashTests/ChatItemCellSelectionTests
```

Expected: PASS, 6 tests.

```bash
./Scripts/test.sh FlipcashTests/ChatTranscriptDiffFuzzTests
```

Expected: PASS, 4 seeds. A failure here names the seed and push index — replay that seed rather than re-running blind.

- [ ] **Step 7: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatItem+Differentiable.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift FlipcashTests/Chat/ChatItemCellSelectionTests.swift FlipcashTests/Chat/ChatTranscriptDiffFuzzTests.swift && git commit -m "feat(chat): dequeue the bare emoji cell for an emoji-only row"
```

---

### Task 10: The notification preview matches the transcript

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatPreviewMapping.swift:84-90`
- Test: `FlipcashCore/Tests/FlipcashCoreTests/ChatMessageRenderingTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `ChatMessageRenderingTests`:

```swift
    @Test("The notification preview flags an emoji-only row the way the transcript does")
    func previewFlagsEmojiOnly() {
        let sender = UUID()
        let messages = [
            ConversationMessage(
                id: MessageID(value: 1), senderID: sender, content: .text("👍"),
                date: Date(timeIntervalSince1970: 1_000_000), unreadSeq: 1
            ),
        ]
        let items = ChatItem.preview(from: messages, selfUserID: sender)
        let rows: [ChatMessage] = items.compactMap { item in
            switch item {
            case .message(let message): return message
            default:                    return nil
            }
        }
        #expect(rows.count == 1)
        #expect(rows[0].rendersAsLargeEmoji)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./Scripts/test.sh FlipcashCoreTests/ChatMessageRenderingTests/previewFlagsEmojiOnly
```

Expected: FAIL — `Expectation failed: rows[0].rendersAsLargeEmoji`.

- [ ] **Step 3: Set the flag in the preview mapper**

In `ChatPreviewMapping.swift`, replace lines 84-90 with:

```swift
            // The same body test the transcript runs, so a notification preview draws a bare emoji
            // the way the conversation behind it will. The bubble-run flags stay false: a preview is
            // at most three rows and never groups them.
            let isEmojiOnly: Bool
            switch message.content {
            case .text(let text): isEmojiOnly = EmojiOnlyDetector.isEmojiOnly(text)
            case .cash, .deleted: isEmojiOnly = false
            }

            items.append(.message(ChatMessage(
                id: String(message.id.value),
                content: content,
                sender: sender,
                isContinuationFromPrevious: false,
                isContinuedByNext: false,
                isEmojiOnly: isEmojiOnly
            )))
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
./Scripts/test.sh FlipcashCoreTests/ChatMessageRenderingTests
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatPreviewMapping.swift FlipcashCore/Tests/FlipcashCoreTests/ChatMessageRenderingTests.swift && git commit -m "feat(chat): flag an emoji-only row in the notification preview"
```

---

## Closing checks

- [ ] **Build the whole app**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

- [ ] **Run the chat suites**

```bash
./Scripts/test.sh FlipcashCoreTests/EmojiOnlyDetectorTests && ./Scripts/test.sh FlipcashCoreTests/ChatMessageRenderingTests && ./Scripts/test.sh FlipcashTests/ChatMessageMappingTests && ./Scripts/test.sh FlipcashTests/ChatViewControllerTests && ./Scripts/test.sh FlipcashTests/ChatItemCellSelectionTests && ./Scripts/test.sh FlipcashTests/ChatEmojiMessageCellTests && ./Scripts/test.sh FlipcashTests/ChatTranscriptDiffFuzzTests && ./Scripts/test.sh FlipcashTests/ChatChangesetFlatteningTests && ./Scripts/test.sh FlipcashTests/ChatReceiptViewTests
```

The full `AllTargets` suite is the user's job — don't run it.

- [ ] **Check by hand, in this order**

1. An ordinary text row's receipt: the "Delivered" reveal and the Delivered→Read swap (Task 7 moved that view).
2. Send one, two and three emoji: bare, 48pt, no bubble, correct side.
3. Send four emoji, and an emoji with text: both keep the bubble.
4. A bubble directly above and below a bare emoji: full 12pt corners, normal gap.
5. In a group chat, a run of `[text, 👍]` from one person: the name sits above the text, the face beside the 👍.
6. Edit an emoji-only message: it stays bare and "Edited" appears on the metadata line.
7. Edit a text message into `👍` and back: the row swaps cell class without the transcript jumping.
8. Reply with an emoji: the bubble stays.
9. Long-press a bare emoji: it lifts with no shadow blob and no rectangular patch behind it.
10. Tap a quote pointing at a bare emoji row: it flashes.

## Risks carried from the spec

- **Notification preview cache.** `ChatMessage` is `Codable` and `NotificationPreviewCache` writes `[ChatItem]` as JSON into the App Group. Swift's synthesized decoder applies no default for a missing key, so a cache written by the previous build fails to decode once the three properties land. The read is `try?` with a live-fetch fallback, so the cost is one slower notification expand per conversation — a one-time expand, not a crash.
- **The metadata row (Task 7)** is the riskiest edit: it moves a view whose implicit-animation suppression is load-bearing and shared by every cell. Check the receipt on a text row before checking anything about emoji.
