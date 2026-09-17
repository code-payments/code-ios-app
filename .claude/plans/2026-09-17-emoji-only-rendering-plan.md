# Emoji-Only Message Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A chat message whose whole body is one to three emoji renders as the emoji alone at 48pt — no bubble, no border, no wash — the way iMessage draws one, while keeping its side, receipt line, avatar gutter, tap-to-retry, swipe-to-reply and context menu.

**Architecture:** Detection is a pure function in `FlipcashCore` (`EmojiOnlyDetector`), called by the transcript mapper. The mapper splits today's single grouping pair into two: `isContinuationFromPrevious`/`isContinuedByNext` keep their values and now mean the *author* run only (name + gutter face), while new `joinsBubbleAbove`/`joinsBubbleBelow` carry the *bubble* run (flattened inner corners, tight row gap). A bare emoji row breaks the bubble run on both sides without touching attribution. A third flag, `isEmojiOnly`, plus a computed `rendersAsLargeEmoji`, put `ChatBubbleView` into a bare mode — the chrome switched off on the view every text row already uses, which is the shape Android shipped. There is no new cell class, so editing a message into or out of emoji-only stays an in-place reconfigure.

**Tech Stack:** Swift 6.1, UIKit (`UICollectionView` + ChatLayout), DifferenceKit, Swift Testing (`import Testing`, `@Suite`/`@Test`, `#expect` — never XCTest), SwiftUI only for `UnevenRoundedRectangle` geometry.

**Spec:** `.claude/plans/2026-09-17-emoji-only-rendering.md`

**Test identifiers:** `./Scripts/test.sh` takes `<Target>/<Suite>[/<TestName>]`, where `<Suite>` is
the **struct** name, not the file name. Several chat test files declare more than one suite —
`ChatViewControllerTests.swift` holds `ChatViewControllerTests` and `ChatRowSpacingTests`, and
`ChatBubbleViewTests.swift` holds `ChatBubbleViewCornerTests`, `ChatMessageCellAlignmentTests` and
`ChatBubbleDeletedTests`. Naming the file runs nothing and reports success. Several identifiers can
go in one invocation.

**Staging:** stage the files each task names, never `git add -A` or `git add .`. A build populates
`Flipcash/Supporting Files/GoogleService-Info.plist` from `code-app-credentials/`, so it sits dirty
in the worktree for the whole run and must never be committed.

**Simulator steps:** `./Scripts/build.sh` defaults to `generic/platform=iOS` — a device build no
simulator can install — so any step that launches the app must pass
`DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'`. Address the simulator by explicit UDID
rather than `booted`: more than one is routinely booted here, `simctl` silently picks one, and a run
that lands on the wrong device gets torn down by whatever else is using it. `simctl launch
--console-pty` never returns, because the app does not exit — background it, let it collect, then
`simctl terminate`. Background it as the command itself rather than with a trailing `&` inside a
script, which gets reaped with its parent shell.

---

## File Structure

**Created**
| File | Responsibility |
|---|---|
| `FlipcashCore/Sources/FlipcashCore/Models/Chat/EmojiOnlyDetector.swift` | Pure "is this body 1–3 emoji?" test |
| `FlipcashCore/Tests/FlipcashCoreTests/EmojiOnlyDetectorTests.swift` | Detector unit tests |
| `FlipcashCore/Tests/FlipcashCoreTests/ChatMessageRenderingTests.swift` | `rendersAsLargeEmoji` gating |

**Modified**
| File | Change |
|---|---|
| `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessage.swift` | Three stored flags + `rendersAsLargeEmoji` |
| `Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift` | Computes the three flags |
| `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatPreviewMapping.swift` | Sets `isEmojiOnly` for the notification preview |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatBubbleView.swift` | Radii read `joinsBubble*`; bare mode — 48pt body, no insets, optional masking path |
| `FlipcashUI/Sources/FlipcashUI/Chat/LinkableBubbleView.swift` | Radii read `joinsBubble*` |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatCashCardCell.swift` | Radii read `joinsBubble*` |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift` | Row gap reads `joinsBubbleBelow` |
| `FlipcashUI/Sources/FlipcashUI/Chat/BubbleBackgroundView.swift` | `apply` takes `bare`: no opaque base, no wash, no border |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatMessageCell.swift` | Asks the column for the "Edited" marker on a bare row |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatColumnCell.swift` | Bottom slot becomes a metadata row (Edited + receipt) |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatReceiptView.swift` | `trailingPadding` promoted to the view |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatScrollBenchmark.swift`, `ChatMotionSandbox.swift`, previews | Mirror the new flags |
| `FlipcashTests/Chat/ChatBubbleViewTests.swift` | Bare row vs ordinary row: chrome, body metrics, lift path |
| `FlipcashTests/Chat/ChatViewControllerTests.swift`, `ChatChangesetFlatteningTests.swift`, `ChatTranscriptDiffFuzzTests.swift`, `ChatMessageMappingTests.swift` | Fixtures + new cases |

**Order:** detection → model → mapper → corner and gap consumers → metadata row → bare bubble → preview cache. Every task ends on a green build.

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
        #expect(EmojiOnlyDetector.isEmojiOnly("🏳️‍🌈"))        // ZWJ on a text-presentation base
        #expect(EmojiOnlyDetector.isEmojiOnly("❤️‍🔥"))        // ZWJ on a text-presentation base
        #expect(EmojiOnlyDetector.isEmojiOnly("👨‍👩‍👧‍👦👍🏽🇺🇸"))   // three of them together
    }

    @Test("Characters that carry the emoji property but render as text do not qualify")
    func emojiPropertyAloneIsNotEnough() {
        #expect(!EmojiOnlyDetector.isEmojiOnly("1"))
        #expect(!EmojiOnlyDetector.isEmojiOnly("#"))
        #expect(!EmojiOnlyDetector.isEmojiOnly("*"))
        #expect(!EmojiOnlyDetector.isEmojiOnly("e\u{0301}"))  // letter + combining mark
        // Bare text-presentation emoji, no variation selector: intentionally excluded. Admitting
        // "❤" would also blow up "™", "©" and "Ⓜ" to 48pt.
        #expect(!EmojiOnlyDetector.isEmojiOnly("\u{2764}"))
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
        #expect(!EmojiOnlyDetector.isEmojiOnly("👍", limit: 0))
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
/// bare and enlarged instead of in a bubble. Pure and synchronous, like `LinkDetector`.
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
    /// The second clause is load-bearing beyond keycaps: a ZWJ sequence whose base has only text
    /// presentation — `🏳️‍🌈`, `❤️‍🔥` — fails the first test and qualifies only because Swift keeps
    /// the U+FE0F on the composed `Character`. Skin-tone modifiers, regional-indicator flags, and a
    /// ZWJ sequence built on an already-emoji-presentation base (`👨‍👩‍👧‍👦`) pass on the first test.
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
    /// one speaker. Attribution only: the inner corner and the row gap are the bubble-run flags' job.
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
        let fiat = ExchangedFiat(
            nativeAmount: FiatAmount(value: 5, currency: .usd),
            rate: Rate(fx: 1, currency: .usd)
        )
        let items = ChatItem.from([
            ConversationMessage(id: MessageID(value: 1), senderID: me, content: .cash(fiat), date: base, unreadSeq: 1),
        ], selfUserID: me)
        let rows = messageRows(items)
        #expect(!rows[0].isEmojiOnly)
        #expect(!rows[0].rendersAsLargeEmoji)
    }

    @Test("A tombstone is never emoji-only, whatever it replaced")
    func tombstoneIsNeverEmojiOnly() {
        let items = ChatItem.from(
            [deleted(1, them, after: 0)],
            selfUserID: me,
            deletedPresentation: .placeholder
        )
        let rows = messageRows(items)
        #expect(!rows[0].isEmojiOnly)
        #expect(!rows[0].rendersAsLargeEmoji)
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
        // What breaks the bubble run: a text body of one to three emoji, on a row that is not a
        // reply — the quote panel lives inside the bubble and has no standalone layout. Narrower
        // than `ChatMessage.rendersAsLargeEmoji`, which also has a link row to rule out.
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
            // otherwise flatten its inner corner to `BubbleBackgroundView.groupedRadius` and take
            // the tight row gap, pointing at a bubble that is not there — while the name and the
            // gutter face stay where they are.
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
./Scripts/test.sh FlipcashTests/ChatRowSpacingTests
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
./Scripts/test.sh FlipcashTests/ChatRowSpacingTests
```

Expected: PASS, including `emojiRowBreaksTheTightGap`.

```bash
./Scripts/test.sh FlipcashTests/ChatChangesetFlatteningTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatBubbleView.swift FlipcashUI/Sources/FlipcashUI/Chat/LinkableBubbleView.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatCashCardCell.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatScrollBenchmark.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatMotionSandbox.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatMessageCell.swift FlipcashTests/Chat/ChatViewControllerTests.swift FlipcashTests/Chat/ChatChangesetFlatteningTests.swift FlipcashTests/Chat/ChatTranscriptDiffFuzzTests.swift && git commit -m "refactor(chat): draw corners and row gaps from the bubble run"
```

---

### Task 5: The column's bottom slot becomes a metadata row

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

- [ ] **Step 7: Drive the receipt animation through the motion sandbox**

The animation this task moves is shared by every cell, and an emoji row is not where a regression
would show first — so it has to be exercised on an ordinary text row. Do not try to do that with a
real account. `ChatMotionSandboxViewController` scripts `.send → .delivered → .read` on a `.me`
text row against the shipping `ChatViewController`, with no server, account or counterpart, and
`--motion-sandbox` stands it up in place of the whole app.

`./Scripts/build.sh` defaults to `generic/platform=iOS`, which produces a device build that no
simulator can install. Override the destination:

```bash
DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro' ./Scripts/build.sh
```

Expected: `** BUILD SUCCEEDED **`.

Then install that build on the booted simulator and launch it with the sandbox argument. Boot one
first if `xcrun simctl list devices booted` comes back empty.

```bash
APP="$(xcodebuild -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}' | head -1)/Flipcash.app"
xcrun simctl install booted "$APP"
xcrun simctl launch --console-pty booted com.flipcash.app.ios --motion-sandbox
```

The launch streams the console and never returns on its own — the app does not exit. Run it in the
background, let it collect for at least 60 seconds (one loop of the script is about 8.6s, so that is
seven), then stop it:

```bash
xcrun simctl terminate booted com.flipcash.app.ios
```

Read the captured console and confirm two things:

1. **No Auto Layout constraint breakage.** Nesting the receipt one stack level deeper is exactly the
   kind of change that produces `Unable to simultaneously satisfy constraints`. The log must be clean
   through at least two loops of the script.
2. **No crash or hang** across the `.reset` beat, which re-pushes the transcript un-animated.

Report the console output either way. The visual check — that "Delivered" still reveals in place
rather than springing in from the stack's origin, and that the Delivered→Read swap does not drag
sideways — is the coordinator's, who captures it from the same harness; your job is to confirm the
run is clean and to say so plainly if it is not.

- [ ] **Step 8: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatColumnCell.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatReceiptView.swift && git commit -m "feat(chat): give a chat row a metadata line for Edited and the receipt"
```

---

### Task 6: The bubble draws bare

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/BubbleBackgroundView.swift:42-61`, `:70-81`, `:83-87`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatBubbleView.swift:51-97`, `:99-101`, `:110-141`, `:167-182`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatMessageCell.swift:45-49`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatScrollBenchmark.swift:249-283`
- Test: `FlipcashTests/Chat/ChatBubbleViewTests.swift`

- [ ] **Step 1: Write the failing tests**

Append a new suite to the end of `FlipcashTests/Chat/ChatBubbleViewTests.swift`:

```swift
@MainActor
@Suite("Bare emoji bubble")
struct ChatBubbleViewBareTests {

    private func bubble(_ message: ChatMessage) -> ChatBubbleView {
        let view = ChatBubbleView()
        view.configure(with: message)
        view.frame = CGRect(x: 0, y: 0, width: 280, height: 80)
        view.layoutIfNeeded()
        return view
    }

    private func chrome(_ view: ChatBubbleView) -> BubbleBackgroundView {
        view.descendants(of: BubbleBackgroundView.self)[0]
    }

    private func body(_ view: ChatBubbleView, _ text: String) -> UILabel? {
        view.descendants(of: UILabel.self).first { $0.text == text }
    }

    @Test("A bare row drops the opaque base, the wash and the border")
    func bareDropsTheChrome() {
        let view = bubble(ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true))
        #expect(chrome(view).backgroundColor == .clear)
        #expect(!chrome(view).isDrawingBubble)
    }

    @Test("An ordinary row still draws all three")
    func ordinaryKeepsTheChrome() {
        let view = bubble(ChatMessage(id: "1", text: "hi", sender: .me))
        #expect(chrome(view).backgroundColor != .clear)
        #expect(chrome(view).isDrawingBubble)
    }

    @Test("A bare row keeps its shape mask, so the attention flash stays rounded")
    func bareKeepsTheMask() {
        let view = bubble(ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true))
        #expect(chrome(view).layer.mask != nil)
    }

    @Test("A bare row draws the body large and flush to the view's edge")
    func bareEnlargesAndUninsetsTheBody() {
        let view = bubble(ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true))
        #expect(body(view, "👍")?.font.pointSize == 48)
        #expect(body(view, "👍")?.frame.minX == 0)
    }

    @Test("An ordinary row keeps the body size and the 12pt inset")
    func ordinaryKeepsTheBodyMetrics() {
        let view = bubble(ChatMessage(id: "1", text: "hi", sender: .me))
        #expect(body(view, "hi")?.font.pointSize == 16)
        #expect(body(view, "hi")?.frame.minX == 12)
    }

    @Test("A bare row has no lift masking path, so nothing casts a bubble-shaped shadow")
    func bareHasNoLiftPath() {
        let view = bubble(ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true))
        #expect(view.maskingPath == nil)
    }

    @Test("An ordinary row still clips its lift preview to the bubble")
    func ordinaryKeepsItsLiftPath() {
        let view = bubble(ChatMessage(id: "1", text: "hi", sender: .me))
        #expect(view.maskingPath != nil)
    }

    @Test("A bare row keeps the Edited marker out of the bubble")
    func bareHidesTheInBubbleMarker() {
        let view = bubble(ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true, isEdited: true))
        let marker = view.descendants(of: UILabel.self).first { $0.text == EditedMarker.text }
        #expect(marker?.isHidden == true)
    }

    @Test("An ordinary edited row still draws the marker in the bubble")
    func ordinaryKeepsTheInBubbleMarker() {
        let view = bubble(ChatMessage(id: "1", text: "hi", sender: .me, isEdited: true))
        let marker = view.descendants(of: UILabel.self).first { $0.text == EditedMarker.text }
        #expect(marker?.isHidden == false)
    }
}
```

Note: `ChatMessage`'s `isEdited` argument comes after `isEmojiOnly` in both inits, so the calls above compile against the signature Task 2 landed. If the argument order differs, fix the call, not the model.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./Scripts/test.sh FlipcashTests/ChatBubbleViewBareTests
```

Expected: compile failure — `value of type 'BubbleBackgroundView' has no member 'isDrawingBubble'`, and `maskingPath` is not optional so `== nil` does not compile.

- [ ] **Step 3: Give `BubbleBackgroundView` a bare mode**

In `BubbleBackgroundView.swift`, in `init(frame:)`, suppress the implicit animation on the view's own background (after `backgroundColor = UIColor(Color.backgroundMain)`, line 46):

```swift
        // Bare mode swaps this to clear, and a reconfigure inside a batch update is an animation
        // context — without this the base cross-fades while the row is moving.
        layer.actions = ["backgroundColor": NSNull()]
```

Give the border layer the same suppression the wash has, and add `hidden` to both, since bare toggles it (replace the `washLayer.actions` line at :49 and add after `borderLayer.lineWidth = 1` at :59):

```swift
        washLayer.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
```

```swift
        borderLayer.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
```

Replace `apply(fill:radii:identity:)` (line 70) with:

```swift
    /// Sets the chrome. `identity` is the row this is drawing — pass it, and a later `apply` for the
    /// same row that changes the radii morphs the corner instead of snapping it. A first setup, a
    /// recycled view taking a new row, and any caller that passes no identity all snap, which is what
    /// keeps a reused cell from animating in someone else's shape.
    ///
    /// `bare` draws no bubble at all, for a row that is only its content.
    func apply(fill: UIColor, radii: RectangleCornerRadii, bare: Bool = false, identity: String? = nil) {
        // The opaque base goes too, not just the wash and the border: it is there so a bubble reads
        // the same under the context menu's dim and the edit blur, and behind a bare row the same
        // base would be a rectangular patch against both.
        backgroundColor = bare ? .clear : UIColor(Color.backgroundMain)
        washLayer.isHidden = bare
        borderLayer.isHidden = bare
        washLayer.backgroundColor = fill.cgColor
        // A recycled view taking a new row drops any flash still running, so the attention never
        // finishes on a message it wasn't meant for.
        if identity != self.identity {
            attentionLayer.removeAnimation(forKey: Self.attentionKey)
        }
        pendingCornerMorph = identity != nil && identity == self.identity && radii != self.radii
        self.identity = identity
        self.radii = radii
        setNeedsLayout()
    }

    /// Whether this chrome draws a bubble: the opaque base, the wash and the hairline border. False
    /// for a bare row, which keeps only the shape mask and the attention layer — the mask because
    /// an unclipped flash would be a rectangle floating where no bubble is.
    var isDrawingBubble: Bool { !washLayer.isHidden }
```

Note the shape mask and `attentionLayer` are deliberately untouched by `bare`.

- [ ] **Step 4: Give `ChatBubbleView` a bare configuration**

In `ChatBubbleView.swift`, add the stored constraints and metrics next to the existing `labelTopToBubble` (after line 31):

```swift
    /// Body insets from the bubble's edges, relaxed to nothing on a bare row so the emoji starts
    /// where the bubble's outer edge would.
    private var labelLeading: NSLayoutConstraint!
    private var labelTrailing: NSLayoutConstraint!
    private var labelBottom: NSLayoutConstraint!
    /// Whether the row currently draws bare, so `maskingPath` can decline to clip a lift preview to
    /// a bubble that is not drawn.
    private var isBare = false

    private static let bodyInset: CGFloat = 12
    private static let bodyPadding: CGFloat = 9
    /// A bare row's padding. Smaller than a bubble's because the emoji carries its own margin
    /// inside its line box, and the transcript's rhythm is what is being matched, not the bubble's.
    private static let barePadding: CGFloat = 4
```

In `setUp()`, build those three as stored constraints. Replace the three lines inside the `NSLayoutConstraint.activate` list that currently read:

```swift
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
```

with:

```swift
            labelBottom,
            labelLeading,
            labelTrailing,
```

and assign them just above the `NSLayoutConstraint.activate` call, next to where `quoteTrailing` is built:

```swift
        labelBottom = label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bodyPadding)
        labelLeading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.bodyInset)
        labelTrailing = label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.bodyInset)
```

Also change `labelTopToBubble`'s literal (line 63) to the constant:

```swift
        labelTopToBubble = label.topAnchor.constraint(equalTo: topAnchor, constant: Self.bodyPadding)
```

Make `maskingPath` optional (line 99):

```swift
    /// The bubble's shape in its own coordinate space, for clipping the context-menu lift preview.
    /// The background is pinned to every edge, so its bounds match the bubble's. `nil` on a bare
    /// row: there is no bubble to clip to, and a lift given no path casts no shadow.
    var maskingPath: UIBezierPath? { isBare ? nil : background.maskingPath }
```

In `configure(with:)`, set the bare state first — before the quote branch, right after the `editedLabel` line:

```swift
        isBare = message.rendersAsLargeEmoji
        labelTopToBubble.constant = isBare ? Self.barePadding : Self.bodyPadding
        labelBottom.constant = isBare ? -Self.barePadding : -Self.bodyPadding
        labelLeading.constant = isBare ? 0 : Self.bodyInset
        labelTrailing.constant = isBare ? 0 : -Self.bodyInset
```

and change the `editedLabel` line above it so a bare row's marker never draws in the bubble — it goes on the metadata line instead:

```swift
        editedLabel.isHidden = !Self.showsEditedMarker(for: message) || message.rendersAsLargeEmoji
```

Finally pass `bare:` to the chrome, in the same `background.apply` call Task 4 already edited:

```swift
        background.apply(
            fill: BubbleBackgroundView.fill(isFromSelf: message.sender == .me),
            radii: BubbleBackgroundView.radii(
                isFromSelf: message.sender == .me,
                groupedAbove: message.joinsBubbleAbove,
                groupedBelow: message.joinsBubbleBelow
            ),
            bare: isBare,
            identity: message.id
        )
```

- [ ] **Step 5: Draw the body at the large size**

In `displayText(for:)`, replace the `bodyFont` binding (line 167) with:

```swift
        let bodyFont: UIFont = if isPlaceholder {
            .italicSystemFont(ofSize: 16)
        } else if message.rendersAsLargeEmoji {
            .default(size: 48, weight: .medium)
        } else {
            .default(size: 16, weight: .medium)
        }
```

and skip the marker's reservation run on a bare row, since the marker is not in the bubble to reserve for (line 180):

```swift
        if Self.showsEditedMarker(for: message), !message.rendersAsLargeEmoji {
            result.append(EditedMarker.reservation)
        }
```

- [ ] **Step 6: Put a bare row's "Edited" on the metadata line**

In `ChatMessageCell.swift`, `configure(with:maxWidth:authorImageData:)` (line 45) becomes:

```swift
    public func configure(with message: ChatMessage, maxWidth: CGFloat, authorImageData: Data? = nil) {
        bubble.configure(with: message)
        maxWidthConstraint.constant = maxWidth
        updateColumn(
            for: message,
            authorImageData: authorImageData,
            showsEditedMarker: message.rendersAsLargeEmoji && message.isEdited
        )
    }
```

`liftPreviewMaskingPath` needs no edit: it already forwards `bubbleView.maskingPath`, which is now optional.

- [ ] **Step 7: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashTests/ChatBubbleViewBareTests FlipcashTests/ChatBubbleViewCornerTests FlipcashTests/ChatBubbleDeletedTests
```

Expected: PASS. The last two are the other suites `ChatBubbleViewTests.swift` already declares — they cover the ordinary bubble this task puts a flag through.

```bash
./Scripts/test.sh FlipcashTests/ChatViewControllerTests
```

Expected: PASS — the lift path changed type, so this is the suite that would catch a break.

- [ ] **Step 8: Make the scroll benchmark produce bare rows**

`ChatScrollBenchmark`'s text pool already holds `"👍"` at index 6, so a qualifying row appears
every eighth message. But `window(_:offset:)` builds each `ChatMessage` directly instead of going
through `ChatItem.from`, so `isEmojiOnly` stays at its `false` default and those rows would still
draw a bubble after this task — the one harness that can show the feature would not show it.

The harness has to make the same two decisions the mapper makes. In
`FlipcashUI/Sources/FlipcashUI/Chat/ChatScrollBenchmark.swift`, inside `window(_:offset:)`, add
above the `for index in 0..<total` loop:

```swift
        // The harness builds messages directly rather than through `ChatItem.from`, so it has to
        // reach the same two conclusions the mapper does: which rows render bare, and where that
        // breaks the bubble run. Without this the pool's emoji row draws a bubble here and not in
        // the app, and the benchmark stops being a picture of the shipping transcript.
        func rendersBare(_ index: Int) -> Bool {
            index >= 0 && index < total && EmojiOnlyDetector.isEmojiOnly(texts[index % texts.count])
        }
```

and replace the four run-flag arguments in the `ChatMessage(...)` call with these five lines:

```swift
                isContinuationFromPrevious: isContinuation,
                isContinuedByNext: isContinued,
                joinsBubbleAbove: isContinuation && !rendersBare(index) && !rendersBare(index - 1),
                joinsBubbleBelow: isContinued && !rendersBare(index) && !rendersBare(index + 1),
                isEmojiOnly: rendersBare(index),
```

Leave `isContinuationFromPrevious` / `isContinuedByNext` exactly as they are — they are the author
run, which a bare row does not break.

`ChatMotionSandbox` needs no equivalent change: no row in its fixture qualifies, and its
`grouped(_:)` doc already says so.

- [ ] **Step 9: Look at it**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

Then stand up a transcript with no account and hold it still — velocity 0 leaves the benchmark's
display link spinning without moving the content, so the capture is repeatable:

```bash
xcrun simctl launch booted com.flipcash.app.ios --scroll-benchmark --scroll-benchmark-messages=24 --scroll-benchmark-authors=4 --scroll-benchmark-velocity=0
```

The pool puts a bare row at indices 6, 14 and 22, so two are on screen at rest. Check the one thing
a unit test cannot reach:

- **the 48pt glyph is not clipped top or bottom.** An emoji fills its line box, and a body line
  height sized for 16pt text crops it. If it crops, set the label's line height explicitly rather
  than reducing the font size — the size is the feature.

Two more need gestures and belong to the coordinator, who drives them from the same harness; say in
your report that you did not check them:

- long-pressing a bare emoji lifts it with no bubble-shaped shadow and no rectangular patch behind
  it, and the same under the edit blur;
- jumping to a bare emoji from a quote flashes a rounded highlight, not a rectangle.

- [ ] **Step 10: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/BubbleBackgroundView.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatBubbleView.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatMessageCell.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatScrollBenchmark.swift FlipcashTests/Chat/ChatBubbleViewTests.swift && git commit -m "feat(chat): render an emoji-only message without a bubble"
```

---
### Task 7: The notification preview matches the transcript

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
./Scripts/test.sh \
  FlipcashCoreTests/EmojiOnlyDetectorTests \
  FlipcashCoreTests/ChatMessageRenderingTests \
  FlipcashTests/ChatMessageMappingTests \
  FlipcashTests/ChatViewControllerTests \
  FlipcashTests/ChatRowSpacingTests \
  FlipcashTests/ChatBubbleViewBareTests \
  FlipcashTests/ChatBubbleViewCornerTests \
  FlipcashTests/ChatBubbleDeletedTests \
  FlipcashTests/ChatMessageCellAlignmentTests \
  FlipcashTests/ChatTranscriptDiffFuzzTests \
  FlipcashTests/ChatChangesetFlatteningTests \
  FlipcashTests/ChatReceiptViewTests
```

The full `AllTargets` suite is the user's job — don't run it.

- [ ] **Check by hand, in this order**

1. An ordinary text row's receipt: the "Delivered" reveal and the Delivered→Read swap (Task 5 moved that view).
2. An ordinary text row generally: the bubble still has its fill, its hairline border and its full corners — Task 6 put a flag through the view every text row uses.
3. Send one, two and three emoji: bare, 48pt, no bubble, correct side.
4. Send four emoji, and an emoji with text: both keep the bubble.
5. A bubble directly above and below a bare emoji: full 12pt corners, normal gap.
6. In a group chat, a run of `[text, 👍]` from one person: the name sits above the text, the face beside the 👍.
7. Edit an emoji-only message: it stays bare and "Edited" appears on the metadata line.
8. Edit a text message into `👍` and back: the row reconfigures in place, with no jump.
9. Reply with an emoji: the bubble stays.
10. Long-press a bare emoji: it lifts with no shadow blob and no rectangular patch behind it.
11. Tap a quote pointing at a bare emoji row: it flashes.

## Risks carried from the spec

- **Notification preview cache.** `ChatMessage` is `Codable` and `NotificationPreviewCache` writes `[ChatItem]` as JSON into the App Group. Swift's synthesized decoder applies no default for a missing key, so a cache written by the previous build fails to decode once the three properties land. The read is `try?` with a live-fetch fallback, so the cost is one slower notification expand per conversation — a one-time expand, not a crash.
- **Bare mode is a flag on the view every text bubble uses (Task 6)**, so a regression there reaches ordinary bubbles rather than staying inside an emoji-only cell. That is the cost of not isolating this in its own cell class; the mitigation is that the bare tests assert the non-bare row still draws its wash, border and base.
- **The metadata row (Task 5)** is the riskiest edit: it moves a view whose implicit-animation suppression is load-bearing and shared by every cell. Check the receipt on a text row before checking anything about emoji.
