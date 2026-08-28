# Messenger Motion Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the tuned Montreal prototype's send / receipt / grouping motion into the shipped UIKit transcript, with a test gate that makes the recorded before/after the only thing left to judge by eye.

**Architecture:** One spring vocabulary (`ChatSpring` + `ChatMotion`) vends the same spring in three forms — SwiftUI `Animation`, `UIView.animate(springDuration:bounce:)`, and `CASpringAnimation` — because iOS 18's `UIView.animate(springDuration:bounce:)` takes SwiftUI's parameters verbatim, so nothing needs converting. The receipt stops being a `String?` and becomes a `ChatReceipt` state, which is what lets a new `ChatReceiptView` cross-fade *between* states instead of cross-fading one label's text. Insertion motion goes through `ChatLayoutDelegate.initialLayoutAttributesForInsertedItem`, the transcript's only hook into ChatLayout's batch-update animation.

**Tech Stack:** Swift 6.1, SwiftUI (bottom bar only), UIKit + `CollectionViewChatLayout` (ChatLayout) + DifferenceKit (transcript), Core Animation (`CASpringAnimation` for `CAShapeLayer.path`), Swift Testing.

**Source spec:** `~/Downloads/Messenger Motion Spec.md`. **Approved design:** [`2026-08-26-messenger-motion-alignment.md`](2026-08-26-messenger-motion-alignment.md).

---

## Corrections to the design doc

Three things turned out differently once the exact code was read. They change what gets built, so they are stated here rather than discovered mid-task.

1. **`keyboardScrollSpring` has no call site.** `ChatViewController.scrollViewDidChangeAdjustedContentInset` (line 141) deliberately sets the offset **unanimated inside UIKit's own keyboard block**, so it already inherits the keyboard curve; the comment there records that forcing a layout pass instead aborts on iOS 26. The spec asks for a zero-bounce spring here for exactly one reason — §7 note 2, "it's riding the system keyboard curve; any overshoot fights it" — and inheriting that curve outright satisfies the reason better than approximating it. Task 1 still defines the constant (the vocabulary is the spec's, and the physics test covers all eight) with a doc comment saying why nothing calls it.

2. **`swapScale` has no shipped counterpart.** §6 scales an action-bar *group* out as a composer fades in. The shipped bar has no action-bar group: `SendCashMorphButton` is one persistent view that morphs its own fill, width and label, which is a better version of that moment. The composer's existing `.transition(.opacity)` already matches the spec's composer half. So Task 13 retunes the spring only.

3. **`ChatMessage.isFailed` becomes computed, not deleted.** Once `receipt` is `ChatReceipt?`, `isFailed` is exactly `receipt == .failed(_)` — the mapping already sets both off the same `message.status == .failed`. Keeping it as a stored property is duplicate state that can disagree. Making it a computed property removes the duplication while leaving all four read sites untouched.

**Out of scope, deliberately:** the rest of §7. Its three notes are SwiftUI-specific — key off `UIResponder` notifications rather than `@FocusState` (the UIKit transcript does this by construction), and the `.scrollEdgeEffectStyle` fade, which the shipped bar does not have. Nothing there describes motion the shipped app is missing.

**Not needed:** no `SQLiteVersion` bump. `ChatMessage` is `Codable` but nothing persists it — it is a display model built fresh on every remap.

---

## File Structure

**Create**

| File | Responsibility |
|---|---|
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatMotion.swift` | `ChatSpring` (one spring, three forms) + the eight named springs, five scale constants, and the pure insertion-attribute geometry. The single source of motion values. |
| `FlipcashUI/Sources/FlipcashUI/Chat/ChatReceiptView.swift` | The two-face receipt: overlaid trailing-aligned faces so Delivered→Read swaps in place. Owns the state, the faces, and the transitions. Contains the fileprivate `ChatReceiptFace` (status + time, 4pt gap). |
| `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatReceipt.swift` | The receipt as a state (`.delivered` / `.read(time:)` / `.failed`) plus its copy split into `status` / `time` / `displayText`. |
| `FlipcashTests/Chat/ChatMotionTests.swift` | Asserts the spring vocabulary against the spec's published physics, and the insertion geometry. |
| `FlipcashTests/Chat/ChatReceiptTests.swift` | The receipt state's copy. |
| `FlipcashTests/Chat/ChatReceiptViewTests.swift` | The receipt view's state machine and layout. |

**Modify**

| File | Change |
|---|---|
| `FlipcashCore/.../Models/Chat/ChatMessage.swift` | `receipt: String?` → `ChatReceipt?`; `isFailed` stored → computed. |
| `Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift:106-138` | Mapping produces a `ChatReceipt` case. |
| `FlipcashUI/.../Chat/ChatReceiptLabel.swift` | 12pt medium → 11pt at a caller-chosen weight; trailing inset moves to `ChatReceiptView`. |
| `FlipcashUI/.../Chat/ChatColumnCell.swift:18,63-113` | `ChatReceiptLabel` → `ChatReceiptView`. |
| `FlipcashUI/.../Chat/ChatViewController.swift:326-353,438-440` | Spring the scroll; implement the layout delegate (insertion + sender-flip spacing); sandbox preview. |
| `FlipcashUI/.../Chat/BubbleBackgroundView.swift:22-58` | Corner morph; grouped radius 6 → 4. |
| `FlipcashUI/.../Chat/ChatBubbleView.swift:62`, `LinkableBubbleView.swift:77`, `ChatCashCardCell.swift:140` | Pass the message id so the morph fires on an in-place regroup, not on cell reuse. |
| `Flipcash/Core/Controllers/ReceiptSettleGate.swift:31` | 0.5s → 0.70s. |
| `Flipcash/Core/Screens/Conversation/ConversationBottomBar.swift:26,95` | Springs routed through `ChatMotion`. |
| 8 test files | Migrated to `ChatReceipt` (enumerated in Task 3). |

---

### Task 0: Capture the "before" recording

This has to happen before a single line changes — there is no way back to it afterwards.

**Files:** none (artifacts only)

- [ ] **Step 1: Build and run the app on the simulator**

Use `mcp__XcodeBuildMCP__session_show_defaults` first to confirm the scheme and simulator, then `mcp__XcodeBuildMCP__build_run_sim`.

- [ ] **Step 2: Record a send and a Delivered→Read at 1x**

Start `mcp__XcodeBuildMCP__record_sim_video`. In the recording: open a conversation, type a message, send it, and let the Delivered receipt appear; then have the counterpart read it so the line becomes Read. Stop the recording.

Save as `~/Downloads/messenger-motion-before-1x.mp4`.

- [ ] **Step 3: Record the same sequence under Slow Animations**

In the Simulator menu, enable Debug ▸ Slow Animations, then repeat Step 2. Save as `~/Downloads/messenger-motion-before-slow.mp4`. Turn Slow Animations back off.

- [ ] **Step 4: Confirm both files exist**

Run: `ls -la ~/Downloads/messenger-motion-before-*.mp4`
Expected: two files, both non-zero size.

There is nothing to commit — the recordings are PR attachments, not repo content.

---

### Task 1: The spring vocabulary

**Files:**
- Create: `FlipcashUI/Sources/FlipcashUI/Chat/ChatMotion.swift`
- Test: `FlipcashTests/Chat/ChatMotionTests.swift`

- [ ] **Step 1: Write the failing test**

Create `FlipcashTests/Chat/ChatMotionTests.swift`:

```swift
//
//  ChatMotionTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import ChatLayout
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("Chat motion vocabulary")
struct ChatMotionTests {

    /// One row of the motion spec's appendix: the published mass-1 physics for a named spring.
    private struct PhysicsRow {
        let name: String
        let spring: ChatSpring
        let dampingRatio: Double
        let stiffness: Double
        let damping: Double
    }

    private static let publishedPhysics: [PhysicsRow] = [
        PhysicsRow(name: "insertion", spring: ChatMotion.insertion, dampingRatio: 0.73, stiffness: 746.3, damping: 39.88),
        PhysicsRow(name: "scroll", spring: ChatMotion.scroll, dampingRatio: 0.88, stiffness: 438.6, damping: 36.86),
        PhysicsRow(name: "keyboardScroll", spring: ChatMotion.keyboardScroll, dampingRatio: 1.00, stiffness: 438.6, damping: 41.89),
        PhysicsRow(name: "delivered", spring: ChatMotion.delivered, dampingRatio: 0.88, stiffness: 246.7, damping: 27.65),
        PhysicsRow(name: "read", spring: ChatMotion.read, dampingRatio: 0.74, stiffness: 584.0, damping: 35.77),
        PhysicsRow(name: "swap", spring: ChatMotion.swap, dampingRatio: 0.69, stiffness: 541.5, damping: 32.11),
        PhysicsRow(name: "sendButton", spring: ChatMotion.sendButton, dampingRatio: 0.66, stiffness: 1366.0, damping: 48.79),
        PhysicsRow(name: "corner", spring: ChatMotion.corner, dampingRatio: 0.68, stiffness: 195.0, damping: 18.99),
    ]

    @Test("Every named spring reproduces the spec's published mass-1 physics")
    func springPhysicsMatchPublishedTable() {
        for row in Self.publishedPhysics {
            #expect(abs(row.spring.dampingRatio - row.dampingRatio) < 0.005, "\(row.name): damping ratio")
            #expect(abs(row.spring.stiffness - row.stiffness) < 0.1, "\(row.name): stiffness")
            #expect(abs(row.spring.damping - row.damping) < 0.01, "\(row.name): damping")
        }
    }

    @Test("A CASpringAnimation carries the spring's physics and runs to its own settling time")
    func layerAnimationCarriesPhysics() {
        let animation = ChatMotion.corner.layerAnimation(keyPath: "path", from: nil, to: nil)
        #expect(animation.keyPath == "path")
        #expect(animation.mass == 1)
        #expect(abs(animation.stiffness - ChatMotion.corner.stiffness) < 0.001)
        #expect(abs(animation.damping - ChatMotion.corner.damping) < 0.001)
        // Core Animation otherwise truncates a spring at the default 0.25s, which would cut the
        // corner morph off less than a third of the way in.
        #expect(animation.duration == animation.settlingDuration)
    }

    @Test("An outgoing insert is anchored to the trailing edge, an incoming one to the leading edge")
    func insertionStateAnchorsToSendersEdge() {
        func attributes() -> ChatLayoutAttributes {
            let attributes = ChatLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
            attributes.frame = CGRect(x: 0, y: 0, width: 400, height: 50)
            return attributes
        }
        // Scaling a 400pt row to 0.95 loses 20pt of width; half of that is the centre shift needed to
        // hold one edge still.
        let expectedShift: CGFloat = 10

        let outgoing = attributes()
        let outgoingCentre = outgoing.center.x
        ChatMotion.applyInsertionState(to: outgoing, sender: .me)
        #expect(outgoing.alpha == 0)
        #expect(outgoing.transform.a == ChatMotion.insertionScale)
        #expect(abs(outgoing.center.x - (outgoingCentre + expectedShift)) < 0.001)

        let incoming = attributes()
        let incomingCentre = incoming.center.x
        ChatMotion.applyInsertionState(to: incoming, sender: .other)
        #expect(abs(incoming.center.x - (incomingCentre - expectedShift)) < 0.001)
    }

    @Test("A row with no sender scales about its own centre")
    func insertionStateWithoutSenderDoesNotShift() {
        let attributes = ChatLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.frame = CGRect(x: 0, y: 0, width: 400, height: 50)
        let centre = attributes.center.x
        ChatMotion.applyInsertionState(to: attributes, sender: nil)
        #expect(attributes.alpha == 0)
        #expect(attributes.transform.a == ChatMotion.insertionScale)
        #expect(attributes.center.x == centre)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./Scripts/test.sh FlipcashTests/ChatMotionTests`
Expected: FAIL to compile — "cannot find 'ChatSpring' in scope" / "cannot find 'ChatMotion' in scope".

- [ ] **Step 3: Write the implementation**

Create `FlipcashUI/Sources/FlipcashUI/Chat/ChatMotion.swift`:

```swift
//
//  ChatMotion.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import ChatLayout
import FlipcashCore

/// A spring in SwiftUI's `(duration, bounce)` parameterization, vended in the three forms the
/// transcript needs: a SwiftUI `Animation`, a `UIView` animation block, and a `CASpringAnimation`
/// for the layer properties `UIView.animate` can't reach (a `CAShapeLayer`'s `path`).
///
/// All three are the *same* spring. `UIView.animate(springDuration:bounce:)` takes SwiftUI's two
/// parameters verbatim, and the Core Animation form derives mass-1 physics from them —
/// `dampingRatio = 1 - bounce`, `stiffness = (2π / duration)²`, `damping = 4π · dampingRatio / duration`.
public struct ChatSpring: Hashable, Sendable {

    /// Perceptual duration — roughly the settle time, not a keyframe length.
    public let duration: Double
    /// `0` is critically damped; `~0.3` reads as a visible overshoot.
    public let bounce: Double

    public init(duration: Double, bounce: Double) {
        self.duration = duration
        self.bounce = bounce
    }

    /// The SwiftUI form, for the bottom bar.
    public var animation: Animation {
        .spring(duration: duration, bounce: bounce)
    }

    public var dampingRatio: Double { 1 - bounce }
    public var stiffness: Double { pow(2 * .pi / duration, 2) }
    public var damping: Double { 4 * .pi * dampingRatio / duration }

    /// Runs `changes` on this spring. Nothing is converted here — `springDuration`/`bounce` are
    /// SwiftUI's own parameters, which is why the vocabulary ports 1:1 into UIKit.
    public func animate(_ changes: @escaping () -> Void, completion: (() -> Void)? = nil) {
        UIView.animate(springDuration: duration, bounce: bounce, initialSpringVelocity: 0) {
            changes()
        } completion: {
            completion?()
        }
    }

    /// A `CASpringAnimation` on `keyPath`, for layer properties `UIView.animate` doesn't drive.
    /// `duration` is set to the spring's own settling time because Core Animation otherwise cuts a
    /// spring off at the default 0.25s.
    public func layerAnimation(keyPath: String, from: Any?, to: Any?) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = stiffness
        animation.damping = damping
        animation.initialVelocity = 0
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        return animation
    }
}

/// The transcript's motion vocabulary: eight named springs and five scale constants, defined once
/// and referenced by name everywhere. The values are the tuned prototype's, transcribed from the
/// motion spec — treat this file as the single place any of them changes.
public enum ChatMotion {

    /// A new bubble arriving.
    public static let insertion = ChatSpring(duration: 0.23, bounce: 0.27)
    /// Every scroll-to-bottom that isn't keyboard-driven.
    public static let scroll = ChatSpring(duration: 0.30, bounce: 0.12)
    /// Zero bounce, for a scroll riding the keyboard curve. **Nothing calls this.** The transcript's
    /// keyboard follow sets the offset unanimated *inside* UIKit's own keyboard block, so it already
    /// inherits that curve — see `ChatViewController.scrollViewDidChangeAdjustedContentInset`, where
    /// forcing a layout pass instead is what aborts on iOS 26. Kept so the vocabulary is complete.
    public static let keyboardScroll = ChatSpring(duration: 0.30, bounce: 0)
    /// The "Delivered" line appearing.
    public static let delivered = ChatSpring(duration: 0.40, bounce: 0.12)
    /// The Delivered → Read label swap.
    public static let read = ChatSpring(duration: 0.26, bounce: 0.26)
    /// The bottom bar's morph between its resting and composing states.
    public static let swap = ChatSpring(duration: 0.27, bounce: 0.31)
    /// The send arrow appearing and clearing with the draft.
    public static let sendButton = ChatSpring(duration: 0.17, bounce: 0.34)
    /// The bubble corner morph as messages group and ungroup. The slowest of the set on purpose — a
    /// quiet detail playing underneath the faster insertion, which shouldn't finish first.
    public static let corner = ChatSpring(duration: 0.45, bounce: 0.32)

    /// Scale a new bubble grows in from.
    public static let insertionScale: CGFloat = 0.95
    /// Scale the receipt grows in from when it first appears.
    public static let deliveredScale: CGFloat = 0.95
    /// Scale "Delivered" shrinks to as it leaves.
    public static let deliveredExitScale: CGFloat = 0.90
    /// Scale "Read" grows in from.
    public static let readEnterScale: CGFloat = 0.90

    /// Where an inserted row starts before it springs into place: transparent, scaled down by
    /// `insertionScale`, and shifted so the shrink is anchored to the sender's own edge — the bubble
    /// grows out of its side of the thread rather than out of thin air. A row with no sender (a date
    /// separator, the typing indicator, the profile card) scales about its centre.
    ///
    /// Pure, and takes the attributes rather than reaching for a collection view, so the geometry is
    /// testable without a layout pass.
    public static func applyInsertionState(to attributes: ChatLayoutAttributes, sender: ChatMessage.Sender?) {
        // Read the width before the transform: setting `frame` on layout attributes resets `transform`.
        let width = attributes.frame.width
        attributes.alpha = 0
        attributes.transform = CGAffineTransform(scaleX: insertionScale, y: insertionScale)
        guard let sender else { return }
        // A row is full-width, so scaling about its centre pulls both edges in by half the lost
        // width. Push the centre back out by that much and the sender's edge stays put.
        let shift = (1 - insertionScale) * width / 2
        attributes.center.x += sender == .me ? shift : -shift
    }
}
#endif
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./Scripts/test.sh FlipcashTests/ChatMotionTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatMotion.swift FlipcashTests/Chat/ChatMotionTests.swift
git commit -m "feat(chat): add the transcript's spring vocabulary"
```

---

### Task 2: `ChatReceipt` as a state

**Files:**
- Create: `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatReceipt.swift`
- Test: `FlipcashTests/Chat/ChatReceiptTests.swift`

- [ ] **Step 1: Write the failing test**

Create `FlipcashTests/Chat/ChatReceiptTests.swift`:

```swift
//
//  ChatReceiptTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import FlipcashCore

@Suite("ChatReceipt copy")
struct ChatReceiptTests {

    @Test("Delivered is a status with no timestamp")
    func delivered() {
        let receipt = ChatReceipt.delivered
        #expect(receipt.status == "Delivered")
        #expect(receipt.time == nil)
        #expect(receipt.displayText == "Delivered")
    }

    @Test("A dated read splits into a bold status and a medium timestamp")
    func readWithTime() {
        let receipt = ChatReceipt.read(time: "3:42 PM")
        #expect(receipt.status == "Read")
        #expect(receipt.time == "3:42 PM")
        #expect(receipt.displayText == "Read 3:42 PM")
    }

    @Test("An undated read is status-only")
    func readWithoutTime() {
        let receipt = ChatReceipt.read(time: nil)
        #expect(receipt.status == "Read")
        #expect(receipt.time == nil)
        #expect(receipt.displayText == "Read")
    }

    @Test("A failure carries its own copy and reports itself as failed")
    func failed() {
        let receipt = ChatReceipt.failed("Not Delivered. Tap to retry")
        #expect(receipt.status == "Not Delivered. Tap to retry")
        #expect(receipt.time == nil)
        #expect(receipt.displayText == "Not Delivered. Tap to retry")
        #expect(receipt.isFailed)
        #expect(!ChatReceipt.delivered.isFailed)
        #expect(!ChatReceipt.read(time: nil).isFailed)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./Scripts/test.sh FlipcashTests/ChatReceiptTests`
Expected: FAIL to compile — "cannot find type 'ChatReceipt' in scope".

- [ ] **Step 3: Write the implementation**

Create `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatReceipt.swift`:

```swift
//
//  ChatReceipt.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The status line under an outgoing bubble, as a state rather than a string. A string can only be
/// cross-faded into another string; a state lets the cell animate *between* two of them —
/// "Delivered" shrinking out while "Read 3:42 PM" grows in over it. The copy still lives in one
/// place: the `status` / `time` split here is also the typographic split the line renders with
/// (bold status, medium timestamp).
public enum ChatReceipt: Hashable, Sendable, Codable {

    /// The message reached the server; the counterpart hasn't read it.
    case delivered
    /// The counterpart read the message. `time` is the relative timestamp ("3:42 PM", "Yesterday",
    /// "Tue, Jun 17"), or nil when the read pointer carries no date.
    case read(time: String?)
    /// The send failed: the line turns red and the row becomes tappable to retry. It carries its own
    /// copy because it's the one state whose text isn't a status + timestamp pair.
    case failed(String)

    /// The bold leading run.
    public var status: String {
        switch self {
        case .delivered: "Delivered"
        case .read: "Read"
        case .failed(let text): text
        }
    }

    /// The medium trailing run, set 4pt after `status` — nil when the state carries no timestamp.
    public var time: String? {
        switch self {
        case .delivered, .failed: nil
        case .read(let time): time
        }
    }

    /// The whole line as one string, for accessibility, logging, and tests.
    public var displayText: String {
        guard let time else { return status }
        return "\(status) \(time)"
    }

    /// Whether this is the failed state — the one that turns the line red and arms retry.
    public var isFailed: Bool {
        switch self {
        case .failed: true
        case .delivered, .read: false
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./Scripts/test.sh FlipcashTests/ChatReceiptTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatReceipt.swift FlipcashTests/Chat/ChatReceiptTests.swift
git commit -m "feat(chat): model the delivery receipt as a state"
```

---

### Task 3: Switch `ChatMessage.receipt` to the state

One commit, because the type change breaks every call site at once. The test step is the migration of the assertions that already cover this.

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Models/Chat/ChatMessage.swift:37-89`
- Modify: `Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift:106-148`
- Modify: `FlipcashTests/Chat/ChatMessageMappingTests.swift`
- Modify: `FlipcashTests/Chat/ChatViewControllerTests.swift`
- Modify: `FlipcashTests/Chat/ChatChangesetFlatteningTests.swift`
- Modify: `FlipcashTests/Chat/ChatCashCardSizingTests.swift`
- Modify: `FlipcashTests/Chat/ChatTranscriptDiffFuzzTests.swift`
- Modify: `FlipcashTests/Chat/ChatLinkMessageCellTests.swift`
- Modify: `FlipcashTests/Regressions/Regression_6a522ee9fdca5cb0d6f21174.swift`
- Modify: `FlipcashTests/Regressions/Regression_6a4f895.swift`

- [ ] **Step 1: Change the model**

In `ChatMessage.swift`, replace the `receipt` and `isFailed` stored properties (lines 37-45) with:

```swift
    /// The status line shown under this bubble, or nil when the row carries none. Carried on the
    /// message — not a separate transcript row — so a send stays a clean insert instead of tearing
    /// the line down and rebuilding it.
    public let receipt: ChatReceipt?
    /// The web link this text row contains, or nil when it carries none — marks the row to render as
    /// tappable text. Derived from the text at map time (not stored/sent) — cash rows never carry one.
    public let linkPreview: LinkPreview?

    /// Whether this row failed to send: turns the status line red and makes the row tappable to
    /// retry. Derived from `receipt` rather than stored alongside it, so the two can't disagree.
    public var isFailed: Bool { receipt?.isFailed ?? false }
```

Then in both initializers, change `receipt: String? = nil` to `receipt: ChatReceipt? = nil` and delete the `isFailed: Bool = false` parameter, its assignment, and its forward in the convenience init. The designated init becomes:

```swift
    public init(
        id: String,
        content: Content,
        sender: Sender,
        isContinuationFromPrevious: Bool = false,
        isContinuedByNext: Bool = false,
        receipt: ChatReceipt? = nil,
        linkPreview: LinkPreview? = nil
    ) {
        self.id = id
        self.content = content
        self.sender = sender
        self.isContinuationFromPrevious = isContinuationFromPrevious
        self.isContinuedByNext = isContinuedByNext
        self.receipt = receipt
        self.linkPreview = linkPreview
    }

    /// Convenience for text rows.
    public init(
        id: String,
        text: String,
        sender: Sender,
        isContinuationFromPrevious: Bool = false,
        isContinuedByNext: Bool = false,
        receipt: ChatReceipt? = nil,
        linkPreview: LinkPreview? = nil
    ) {
        self.init(
            id: id,
            content: .text(text),
            sender: sender,
            isContinuationFromPrevious: isContinuationFromPrevious,
            isContinuedByNext: isContinuedByNext,
            receipt: receipt,
            linkPreview: linkPreview
        )
    }
```

- [ ] **Step 2: Change the mapping**

In `ChatItem+Conversation.swift`, replace the receipt block (lines 106-138) with:

```swift
            // The status line rides on the bubble itself (not a separate row, so a send is a clean
            // insert). All of its copy is produced here, in one layer; the cell only styles it
            // (resting vs. red + tappable) off the state.
            let receipt: ChatReceipt?
            switch message.status {
            case .sent:
                // "Delivered"/"Read" rides only the latest confirmed self message — preserved even when
                // a later send is in flight or failed, and held back while the row is still settling in.
                // `latestSentFromSelfID` is already a self+sent row, so matching it implies both.
                receipt = message.stableID == latestSentFromSelfID && message.stableID != suppressReceiptFor
                    ? Self.receipt(for: message.id, counterpartRead: counterpartRead)
                    : nil
            case .sending:
                // No status line while in flight — the bubble sits there until it resolves to
                // "Delivered" or the failed state.
                receipt = nil
            case .failed:
                receipt = .failed("Not Delivered. Tap to retry")
            }

            items.append(.message(ChatMessage(
                id: message.stableID,
                content: content,
                sender: isFromSelf ? .me : .other,
                isContinuationFromPrevious: groupedAbove,
                isContinuedByNext: groupedBelow,
                receipt: receipt,
                linkPreview: linkPreview
            )))
```

Then replace `receiptText(for:counterpartRead:)` (lines 143-147) with:

```swift
    /// The read state once the counterpart's read pointer reaches the message, else delivered. The
    /// timestamp is relative — "3:42 PM" today, "Yesterday", "Monday", "Tue, Jun 17".
    nonisolated private static func receipt(for messageID: MessageID, counterpartRead: (pointer: MessageID, date: Date?)?) -> ChatReceipt {
        guard let read = counterpartRead, read.pointer >= messageID else { return .delivered }
        guard let date = read.date else { return .read(time: nil) }
        return .read(time: date.formattedRelatively(useTimeForToday: true))
    }
```

- [ ] **Step 3: Migrate the tests**

`ChatMessageMappingTests.swift` — the helper at line 41 keeps its shape, reading through `displayText`:

```swift
    private func receiptText(_ items: [ChatItem]) -> String? {
        items.compactMap { if case .message(let message) = $0 { message.receipt?.displayText } else { nil } }.last
    }
```

Then change the four direct comparisons to compare states instead of strings:

- line 235: `#expect(rows.first?.receipt == "Delivered")` → `#expect(rows.first?.receipt == .delivered)`
- line 252: `#expect(rows.first?.receipt == "Delivered")` → `#expect(rows.first?.receipt == .delivered)`
- line 253: `#expect(rows.last?.receipt == "Not Delivered. Tap to retry")` → `#expect(rows.last?.receipt == .failed("Not Delivered. Tap to retry"))`
- lines 204-205 (`receipt(_:)` local helper): change its return type to `ChatReceipt?` and the assertion to `#expect(receipt("3") == .delivered)`.

The `displayText`-based assertions at lines 73, 165, 175 and 221 need no change.

`ChatChangesetFlatteningTests.swift` — the helper's parameter type at line 26: `receipt: String? = nil` → `receipt: ChatReceipt? = nil`. Then lines 42 and 45: `receipt: "Delivered"` → `receipt: .delivered`.

`ChatTranscriptDiffFuzzTests.swift` — line 61: `receipt: receipt ? "Read" : nil` → `receipt: receipt ? .read(time: nil) : nil`.

`ChatViewControllerTests.swift` — lines 79 and 89: `receipt: "Delivered"` → `receipt: .delivered`.

`ChatCashCardSizingTests.swift` — line 56: `receipt: "Delivered"` → `receipt: .delivered`.

`ChatLinkMessageCellTests.swift` — line 21: `isFailed: true,` → `receipt: .failed("Not Delivered. Tap to retry"),`.

`Regression_6a522ee9fdca5cb0d6f21174.swift` — lines 71 and 90: `receipt: "Read"` → `receipt: .read(time: nil)`.

`Regression_6a4f895.swift` — line 24 helper parameter: `receipt: String? = nil` → `receipt: ChatReceipt? = nil`; line 63: `receipt: "Delivered"` → `receipt: .delivered`.

- [ ] **Step 4: Fix the one remaining source site**

In `ChatColumnCell.updateColumn(for:)`, one line passes `message.receipt` into `setReceipt(_:animated:)`, which takes a `String?`. Until Task 6 replaces that method wholesale, keep it compiling by passing the flattened text:

```swift
        setReceipt(message.receipt, animated: isInPlaceUpdate && window != nil)
```

becomes

```swift
        setReceipt(message.receipt?.displayText, animated: isInPlaceUpdate && window != nil)
```

`ChatLinkMessageCell.swift:53` and `ChatColumnCell.swift:85-87` read `message.isFailed`, which is now computed — they need no change.

- [ ] **Step 5: Run the affected suites**

Run: `./Scripts/test.sh FlipcashTests/ChatMessageMappingTests FlipcashTests/ChatChangesetFlatteningTests FlipcashTests/ChatViewControllerTests FlipcashTests/ChatTranscriptDiffFuzzTests FlipcashTests/ChatLinkMessageCellTests FlipcashTests/ChatCashCardSizingTests`
Expected: PASS, all suites. Behaviour is unchanged — this is a type migration.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(chat): carry the delivery receipt as a state, not a string"
```

---

### Task 4: Restyle the receipt label

§9 puts the line at 11pt with a bold status and a medium timestamp. That's two runs, so the label stops being one styled thing and becomes a styled thing at a caller-chosen weight. The 10pt trailing padding moves out to the container in Task 5, where it applies once to the pair rather than to each label.

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatReceiptLabel.swift`

- [ ] **Step 1: Rewrite the label**

Replace the whole body of `ChatReceiptLabel.swift` with:

```swift
//
//  ChatReceiptLabel.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

/// One run of the "Delivered" / "Read 3:42 PM" line under the user's latest sent bubble: the status
/// in bold, the timestamp in medium. A styled label the receipt view embeds — not a standalone
/// transcript row — so it sizes and animates with its bubble instead of inserting and moving on its
/// own. The line's trailing padding lives on `ChatReceiptView`, which owns the pair.
public final class ChatReceiptLabel: UILabel {

    /// Resting color of the receipt line (Delivered/Read).
    public static let defaultColor = UIColor.white.withAlphaComponent(0.5)
    /// Color of the failed status line: the theme's error-text token, which tracks appearance changes.
    public static let failedColor = UIColor(Color.textError)

    /// The line's type size. Both runs share it; only the weight differs.
    public static let fontSize: CGFloat = 11

    public init(weight: UIFont.Weight) {
        super.init(frame: .zero)
        font = .default(size: Self.fontSize, weight: weight)
        textColor = Self.defaultColor
        textAlignment = .right
        numberOfLines = 1
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
#endif
```

- [ ] **Step 2: Keep `ChatColumnCell` compiling**

`ChatColumnCell.swift:18` constructs the label with no arguments. Change it to the bold run for now — Task 6 replaces this line entirely:

```swift
    private let receipt = ChatReceiptLabel(weight: .bold)
```

- [ ] **Step 3: Run the chat suites to confirm nothing regressed**

Run: `./Scripts/test.sh FlipcashTests/ChatViewControllerTests FlipcashTests/ChatBubbleViewCornerTests FlipcashTests/ChatMessageCellAlignmentTests FlipcashTests/ChatLinkMessageCellTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatReceiptLabel.swift FlipcashUI/Sources/FlipcashUI/Chat/ChatColumnCell.swift
git commit -m "refactor(chat): make the receipt label one run at a caller-chosen weight"
```

---

### Task 5: `ChatReceiptView`

**Files:**
- Create: `FlipcashUI/Sources/FlipcashUI/Chat/ChatReceiptView.swift`
- Test: `FlipcashTests/Chat/ChatReceiptViewTests.swift`

- [ ] **Step 1: Write the failing test**

Create `FlipcashTests/Chat/ChatReceiptViewTests.swift`:

```swift
//
//  ChatReceiptViewTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatReceiptView state machine")
struct ChatReceiptViewTests {

    private func view() -> ChatReceiptView {
        ChatReceiptView(frame: CGRect(x: 0, y: 0, width: 200, height: 20))
    }

    @Test("A nil receipt renders nothing and takes no height")
    func nilReceiptIsEmpty() {
        let view = view()
        view.apply(nil, animated: false)
        #expect(view.isHidden)
        #expect(view.currentStatusText == nil)
    }

    @Test("Delivered renders a bold status and no timestamp")
    func deliveredRendersStatusOnly() {
        let view = view()
        view.apply(.delivered, animated: false)
        #expect(!view.isHidden)
        #expect(view.currentStatusText == "Delivered")
        #expect(view.currentTimeText == nil)
    }

    @Test("A dated read renders both runs")
    func readRendersStatusAndTime() {
        let view = view()
        view.apply(.read(time: "3:42 PM"), animated: false)
        #expect(view.currentStatusText == "Read")
        #expect(view.currentTimeText == "3:42 PM")
    }

    @Test("Delivered to Read swaps in place, leaving the outgoing text on the back face")
    func deliveredToReadSwapsInPlace() {
        let view = view()
        view.apply(.delivered, animated: false)
        view.apply(.read(time: "3:42 PM"), animated: true)
        // The front face carries the arriving state; the outgoing one is handed to the back face so
        // both are on screen for the length of the cross-fade.
        #expect(view.currentStatusText == "Read")
        #expect(view.outgoingStatusText == "Delivered")
    }

    @Test("A failed receipt turns the line red; a resolved one turns it back")
    func failedReceiptIsRed() {
        let view = view()
        view.apply(.failed("Not Delivered. Tap to retry"), animated: false)
        #expect(view.currentStatusText == "Not Delivered. Tap to retry")
        #expect(view.currentStatusColor == ChatReceiptLabel.failedColor)
        view.apply(.delivered, animated: false)
        #expect(view.currentStatusColor == ChatReceiptLabel.defaultColor)
    }

    @Test("Re-applying the same receipt is a no-op, so a remap can't restart the swap")
    func reapplyingSameReceiptDoesNotSwap() {
        let view = view()
        view.apply(.delivered, animated: false)
        view.apply(.read(time: "3:42 PM"), animated: true)
        view.apply(.read(time: "3:42 PM"), animated: true)
        // The back face still holds the *original* outgoing state — the second apply did nothing.
        #expect(view.outgoingStatusText == "Delivered")
    }

    @Test("Clearing the receipt collapses the line without animating it away")
    func clearingCollapses() {
        let view = view()
        view.apply(.delivered, animated: false)
        view.apply(nil, animated: true)
        #expect(view.isHidden)
        #expect(view.currentStatusText == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./Scripts/test.sh FlipcashTests/ChatReceiptViewTests`
Expected: FAIL to compile — "cannot find 'ChatReceiptView' in scope".

- [ ] **Step 3: Write the implementation**

Create `FlipcashUI/Sources/FlipcashUI/Chat/ChatReceiptView.swift`:

```swift
//
//  ChatReceiptView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// The status line under an outgoing bubble, animated as a state machine rather than a text swap:
/// two overlaid trailing-aligned faces, so "Delivered" shrinks out while "Read 3:42 PM" grows in
/// over it, in place. It owns the current state, both faces, and the transitions between them —
/// more than a couple of pieces of state, so it is its own unit rather than fields on the cell.
///
/// `front` always carries the current state and is the only face that drives the view's size;
/// `back` only ever holds a state on its way out. The roles never swap, which is what keeps the
/// layout static across a cross-fade.
final class ChatReceiptView: UIView {

    /// Keeps the line off the bubble's trailing edge.
    private static let trailingPadding: CGFloat = 10

    private let front = ChatReceiptFace()
    private let back = ChatReceiptFace()
    private var receipt: ChatReceipt?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true

        // `back` is added first so the outgoing state passes underneath the arriving one.
        for face in [back, front] {
            face.translatesAutoresizingMaskIntoConstraints = false
            addSubview(face)
        }
        NSLayoutConstraint.activate([
            // The front face defines the view's size.
            front.topAnchor.constraint(equalTo: topAnchor),
            front.bottomAnchor.constraint(equalTo: bottomAnchor),
            front.leadingAnchor.constraint(equalTo: leadingAnchor),
            front.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingPadding),
            // The back face is pinned over it and sizes itself, so an outgoing state of a different
            // width can't resize the row on its way out.
            back.trailingAnchor.constraint(equalTo: front.trailingAnchor),
            back.centerYAnchor.constraint(equalTo: front.centerYAnchor),
        ])
        back.alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Render `receipt`, animating between states when `animated` (the same row changing in place).
    /// Arrival scales in from `deliveredScale` on the delivered spring; a status swap cross-fades in
    /// place on the faster, bouncier read spring; clearing is instant, so the row collapses in step
    /// with the batch update rather than after a fade.
    func apply(_ receipt: ChatReceipt?, animated: Bool) {
        guard receipt != self.receipt else { return }
        let previous = self.receipt
        self.receipt = receipt

        guard let receipt else {
            reset()
            return
        }

        isHidden = false

        guard animated else {
            back.alpha = 0
            setFront(receipt)
            front.alpha = 1
            front.transform = .identity
            return
        }

        guard let previous else {
            // First appearance: the line grows in from `deliveredScale`, with nothing to cross-fade
            // against.
            back.alpha = 0
            setFront(receipt)
            front.alpha = 0
            front.transform = CGAffineTransform(scaleX: ChatMotion.deliveredScale, y: ChatMotion.deliveredScale)
            ChatMotion.delivered.animate { [front] in
                front.alpha = 1
                front.transform = .identity
            }
            return
        }

        // A status swap: hand the outgoing state to the back face so both are on screen, then run
        // them past each other. Both slide distances are tuned to zero — this is a pure in-place
        // scale cross-fade, which reads cleaner at this type size than a horizontal pass.
        back.apply(status: previous.status, time: previous.time)
        back.setColor(previous.isFailed ? ChatReceiptLabel.failedColor : ChatReceiptLabel.defaultColor)
        back.alpha = 1
        back.transform = .identity

        setFront(receipt)
        front.alpha = 0
        front.transform = CGAffineTransform(scaleX: ChatMotion.readEnterScale, y: ChatMotion.readEnterScale)

        ChatMotion.read.animate { [front, back] in
            back.alpha = 0
            back.transform = CGAffineTransform(scaleX: ChatMotion.deliveredExitScale, y: ChatMotion.deliveredExitScale)
            front.alpha = 1
            front.transform = .identity
        }
    }

    /// Drop any in-flight transition and collapse to empty — the cell is being recycled, or the
    /// receipt cleared.
    func reset() {
        receipt = nil
        for face in [front, back] {
            face.layer.removeAllAnimations()
            face.transform = .identity
            face.setColor(ChatReceiptLabel.defaultColor)
        }
        front.alpha = 1
        back.alpha = 0
        isHidden = true
    }

    /// Put `receipt` on the front face, in its resting or failed colour.
    private func setFront(_ receipt: ChatReceipt) {
        front.apply(status: receipt.status, time: receipt.time)
        front.setColor(receipt.isFailed ? ChatReceiptLabel.failedColor : ChatReceiptLabel.defaultColor)
    }

    // MARK: - Test hooks

    /// The status run currently on the front face, or nil when the line is empty.
    var currentStatusText: String? { receipt == nil ? nil : front.statusText }
    /// The timestamp run currently on the front face.
    var currentTimeText: String? { receipt == nil ? nil : front.timeText }
    /// The status run on the back face — whatever is on its way out.
    var outgoingStatusText: String? { back.statusText }
    /// The front face's status colour, which is what makes a failed line read as red.
    var currentStatusColor: UIColor? { front.statusColor }
}

/// One rendering of a receipt: the bold status, then the medium timestamp 4pt after it. The
/// timestamp collapses when the state carries none, so "Delivered" sits flush to the trailing edge
/// exactly as "3:42 PM" would.
private final class ChatReceiptFace: UIView {

    /// Gap between the status and the timestamp.
    private static let runSpacing: CGFloat = 4

    private let statusLabel = ChatReceiptLabel(weight: .bold)
    private let timeLabel = ChatReceiptLabel(weight: .medium)

    /// Trailing edge when the state carries no timestamp.
    private var statusTrailing: NSLayoutConstraint!
    /// Trailing edge and the gap that positions it, when the state does carry one.
    private var timeTrailing: NSLayoutConstraint!
    private var timeLeading: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        for label in [statusLabel, timeLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        statusTrailing = statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        timeTrailing = timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        timeLeading = timeLabel.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: Self.runSpacing)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: topAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            timeLabel.firstBaselineAnchor.constraint(equalTo: statusLabel.firstBaselineAnchor),
            statusTrailing,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Show `status`, followed by `time` when there is one. Which constraint holds the trailing edge
    /// switches with it, so the line stays flush either way.
    func apply(status: String, time: String?) {
        statusLabel.text = status
        timeLabel.text = time
        timeLabel.isHidden = time == nil
        if time == nil {
            NSLayoutConstraint.deactivate([timeLeading, timeTrailing])
            statusTrailing.isActive = true
        } else {
            statusTrailing.isActive = false
            NSLayoutConstraint.activate([timeLeading, timeTrailing])
        }
    }

    /// Both runs share a colour — the resting white @ 50%, or the error token when failed.
    func setColor(_ color: UIColor) {
        statusLabel.textColor = color
        timeLabel.textColor = color
    }

    var statusText: String? { statusLabel.text }
    var timeText: String? { timeLabel.isHidden ? nil : timeLabel.text }
    var statusColor: UIColor? { statusLabel.textColor }
}
#endif
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./Scripts/test.sh FlipcashTests/ChatReceiptViewTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatReceiptView.swift FlipcashTests/Chat/ChatReceiptViewTests.swift
git commit -m "feat(chat): cross-fade Delivered into Read in place"
```

---

### Task 6: Wire the receipt view into the cell

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatColumnCell.swift:18,63-113`

- [ ] **Step 1: Swap the label for the view**

Line 18:

```swift
    private let receipt = ChatReceiptView(frame: .zero)
```

- [ ] **Step 2: Simplify reuse**

Replace `prepareForReuse` (lines 63-72) with:

```swift
    public override func prepareForReuse() {
        super.prepareForReuse()
        currentMessageID = nil
        retryID = nil
        retryTap?.isEnabled = false
        // Clear the line so a recycled cell never carries its prior row's state into the next use.
        receipt.reset()
    }
```

- [ ] **Step 3: Route the state through, and delete `setReceipt`**

In `updateColumn(for:)`, these three lines:

```swift
        receipt.textColor = message.isFailed ? ChatReceiptLabel.failedColor : ChatReceiptLabel.defaultColor
        retryTap?.isEnabled = message.isFailed
        setReceipt(message.receipt?.displayText, animated: isInPlaceUpdate && window != nil)
```

become two — the colour now travels with the state, so the cell stops deciding it:

```swift
        retryTap?.isEnabled = message.isFailed
        receipt.apply(message.receipt, animated: isInPlaceUpdate && window != nil)
```

Then delete the whole `setReceipt(_:animated:)` method, and update `updateColumn(for:)`'s doc comment, which currently says the cell styles the text:

```swift
    /// Sets the status line and hugs the column to the sender's edge. Call from `configure`. The
    /// state is supplied by the mapping (`message.receipt`); this only decides whether the change
    /// animates in place — the resting-vs-failed styling travels with the state itself.
```

The type's own doc comment (line 12) says the column stacks content above "an optional `ChatReceiptLabel`" — change that to `ChatReceiptView`.

- [ ] **Step 4: Run the chat suites**

Run: `./Scripts/test.sh FlipcashTests/ChatViewControllerTests FlipcashTests/ChatBubbleViewCornerTests FlipcashTests/ChatMessageCellAlignmentTests FlipcashTests/ChatLinkMessageCellTests FlipcashTests/ChatCashCardSizingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatColumnCell.swift
git commit -m "feat(chat): render the receipt line from its state"
```

---

### Task 7: Spring the insertion

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift:438-440`

- [ ] **Step 1: Implement the delegate**

Replace the empty conformance at lines 438-440 with:

```swift
/// The controller is the layout delegate: cells inherit ChatLayout's defaults for sizing and
/// alignment, and the two hooks below carry the transcript's motion — how an inserted row starts,
/// and the extra breathing room where the speaker changes.
extension ChatViewController: ChatLayoutDelegate {

    public func initialLayoutAttributesForInsertedItem(
        _ chatLayout: CollectionViewChatLayout,
        at indexPath: IndexPath,
        modifying originalAttributes: ChatLayoutAttributes,
        on state: InitialAttributesRequestType
    ) {
        switch state {
        case .initial:
            ChatMotion.applyInsertionState(to: originalAttributes, sender: sender(at: indexPath))
        case .invalidation:
            // A re-measure of a row already on screen, not an arrival. Scaling here would make
            // settled rows pop every time a cell self-sizes, so keep ChatLayout's default.
            originalAttributes.alpha = 0
        }
    }

    /// Which side of the thread the row at `indexPath` belongs to, or nil for a row that belongs to
    /// neither (a date separator, the profile card). The typing indicator counts as the counterpart:
    /// it is an incoming bubble in everything but content, so it should arrive like one and should
    /// not read as a change of speaker when it follows their message.
    ///
    /// Bounds-checked, because the layout can ask mid-batch-update, where an index path may outrun
    /// `items`.
    private func sender(at indexPath: IndexPath) -> ChatMessage.Sender? {
        guard items.indices.contains(indexPath.item) else { return nil }
        switch items[indexPath.item] {
        case .message(let message): return message.sender
        case .typingIndicator: return .other
        case .dateSeparator, .profileCard: return nil
        }
    }
}
```

- [ ] **Step 2: Wrap the batch update in the insertion spring**

In `update(items:animated:)`, wrap the `collectionView.reload(using:)` call (lines 200-222) so `performBatchUpdates` inherits the spring:

```swift
        isUpdating = true
        // `performBatchUpdates` inherits the enclosing animation's timing, which is the only way to
        // give ChatLayout's insertion a spring — the delegate above supplies the *starting* state,
        // this supplies the curve it travels on.
        ChatMotion.insertion.animate { [weak self] in
            guard let self else { return }
            collectionView.reload(
                using: changeset,
                // A change too large to animate falls back to a reload that keeps the bottom-anchored
                // position rather than animating hundreds of rows.
                interrupt: { $0.changeCount > 100 },
                onInterruptedReload: { [weak self] in
                    guard let self else { return }
                    let snapshot = chatLayout.getContentOffsetSnapshot(from: .bottom)
                    collectionView.reloadData()
                    if let snapshot {
                        chatLayout.restoreContentOffset(with: snapshot)
                    }
                },
                completion: { [weak self] _ in
                    self?.isUpdating = false
                },
                setData: { [weak self] data in
                    self?.items = data
                }
            )
        }
```

This also covers §4's typing-indicator entry, which asks for the same spring and the same 0.95 scale anchored to the leading edge as an incoming bubble — `sender(at:)` reporting `.other` for it is what makes that fall out rather than needing its own path.

**If this doesn't take:** DifferenceKit runs *staged* batch updates, and a multi-stage changeset may not inherit the outer timing. The fallback recorded in the design doc is to drop this wrap entirely — leave `collectionView.reload(using:)` as it was — and keep only the delegate from Step 1, accepting UIKit's default ease on the travel while still getting the scale-from-the-sender's-edge start. Decide by watching Task 14's sandbox, not by argument. If you take the fallback, say so in the commit body.

- [ ] **Step 3: Run the transcript suites**

Run: `./Scripts/test.sh FlipcashTests/ChatViewControllerTests FlipcashTests/ChatTranscriptDiffFuzzTests FlipcashTests/ChatChangesetFlatteningTests`
Expected: PASS. The fuzz suite is the one that matters here — it exercises the diff hard enough to catch a batch update that no longer applies cleanly.

- [ ] **Step 4: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift
git commit -m "feat(chat): grow an arriving bubble out of its own edge"
```

---

### Task 8: Spring the scroll

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift:344-353`

- [ ] **Step 1: Replace the fixed curve**

In `scrollToBottom(animated:)`, replace the `UIView.animate(withDuration: 0.25, ...)` block with:

```swift
        ChatMotion.scroll.animate { [collectionView] in
            collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        } completion: { [weak self] in
            // Lock to the exact bottom edge once the animation lands (the estimate may have moved).
            self?.chatLayout.restoreContentOffset(with: snapshot)
        }
```

The `guard target > collectionView.contentOffset.y else { return }` above it stays as-is.

- [ ] **Step 2: Run the transcript suites**

Run: `./Scripts/test.sh FlipcashTests/ChatViewControllerTests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift
git commit -m "feat(chat): spring the scroll to the newest message"
```

---

### Task 9: Morph the bubble corners

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/BubbleBackgroundView.swift:22-58`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatBubbleView.swift:62`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/LinkableBubbleView.swift:77`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatCashCardCell.swift:140`

- [ ] **Step 1: Animate the path on an in-place radii change**

In `BubbleBackgroundView.swift`, add two stored properties beside `radii`:

```swift
    /// The message this chrome currently draws, so a radii change can be told apart from a recycled
    /// view being set up for a different row. A view with no identity never morphs.
    private var identity: String?
    /// Set by `apply` when the radii changed in place; consumed by the next `layoutSubviews`, which
    /// is where the path is actually built.
    private var pendingCornerMorph = false
```

Replace `apply(fill:radii:)` with:

```swift
    /// Sets the chrome. `identity` is the row this is drawing — pass it and a later `apply` for the
    /// same row that changes the radii morphs the corner instead of snapping it. A first setup, a
    /// recycled view taking a new row, and any caller that passes no identity all snap, which is
    /// what keeps a reused cell from animating in someone else's shape.
    func apply(fill: UIColor, radii: RectangleCornerRadii, identity: String? = nil) {
        backgroundColor = fill
        pendingCornerMorph = identity != nil && identity == self.identity && radii != self.radii
        self.identity = identity
        self.radii = radii
        setNeedsLayout()
    }
```

Replace `layoutSubviews` with:

```swift
    override func layoutSubviews() {
        super.layoutSubviews()
        let previous = shapeMask.path
        let path = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: bounds).cgPath
        shapeMask.path = path
        borderLayer.path = path
        borderLayer.frame = bounds

        // A `CAShapeLayer`'s `path` isn't animatable through `UIView.animate`, so the corner morph is
        // its own explicit spring. It's the slowest in the vocabulary on purpose: a quiet detail
        // playing underneath the faster insertion.
        guard pendingCornerMorph, let previous else { return }
        pendingCornerMorph = false
        for layer in [shapeMask, borderLayer] {
            layer.add(ChatMotion.corner.layerAnimation(keyPath: "path", from: previous, to: path), forKey: "cornerMorph")
        }
    }
```

- [ ] **Step 2: Pass the identity from the three bubble callers**

`ChatBubbleView.swift`, in the `apply` call at line 62, add the trailing argument:

```swift
            identity: message.id
```

Do the same in `LinkableBubbleView.swift:77` and `ChatCashCardCell.swift:140`. `ChatTypingIndicatorCell.swift:43` passes nothing — it never regroups, so it must keep snapping.

- [ ] **Step 3: Run the bubble suites**

Run: `./Scripts/test.sh FlipcashTests/ChatBubbleViewCornerTests FlipcashTests/ChatMessageCellAlignmentTests FlipcashTests/LinkableBubbleViewTests FlipcashTests/ChatCashCardSizingTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/
git commit -m "feat(chat): morph the shared corner when bubbles group"
```

---

### Task 10: The §9 layout values

Two of these are visual design changes, not motion. Implement the spec's numbers and raise them with Ted before merge (see Risks).

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/BubbleBackgroundView.swift:24`
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift` (delegate extension from Task 7)

- [ ] **Step 1: Tighten the grouped radius**

`BubbleBackgroundView.swift:24`:

```swift
    static let groupedRadius: CGFloat = 4
```

Update the type's doc comment (line 13) and `radii(isFromSelf:groupedAbove:groupedBelow:)`'s (line 68), both of which say "12 to 6", to say "12 to 4".

`ChatBubbleViewCornerTests` reads the value through `BubbleBackgroundView.groupedRadius`, so its assertions still hold — but three of its comments name the number. Update them too, or they become lies:

```swift
    private let grouped = BubbleBackgroundView.groupedRadius // 4
```

and the two `// inner bottom flattened to 6` / `// inner top flattened to 6` trailing comments, to `4`.

- [ ] **Step 2: Widen the gap where the speaker changes**

Add to `ChatViewController`'s constants (beside `bottomThreshold`, line 55):

```swift
    /// Extra spacing where the sender flips, on top of the base inter-item spacing, so a change of
    /// speaker reads as a break in the column rather than another row in the same run.
    private static let senderFlipExtraSpacing: CGFloat = 6
```

Add to the `ChatLayoutDelegate` extension from Task 7:

```swift
    public func interItemSpacing(_ chatLayout: CollectionViewChatLayout, after indexPath: IndexPath) -> CGFloat? {
        // Only a message→message pair with different senders widens. Any other pairing (into or out
        // of a separator, the typing indicator, the profile card) takes the base spacing.
        guard let current = sender(at: indexPath),
              let next = sender(at: IndexPath(item: indexPath.item + 1, section: indexPath.section)),
              current != next else { return nil }
        return chatLayout.settings.interItemSpacing + Self.senderFlipExtraSpacing
    }
```

- [ ] **Step 3: Run the transcript suites**

Run: `./Scripts/test.sh FlipcashTests/ChatViewControllerTests FlipcashTests/ChatBubbleViewCornerTests FlipcashTests/ChatMessageCellAlignmentTests FlipcashTests/ChatCashCardSizingTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/
git commit -m "feat(chat): tighten the grouped corner and break the column at a sender flip"
```

---

### Task 11: The settle floor

**Files:**
- Modify: `Flipcash/Core/Controllers/ReceiptSettleGate.swift:31`
- Modify: `FlipcashTests/Chat/ReceiptSettleGateTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `ReceiptSettleGateTests.swift`, inside the suite:

```swift
    @Test("The default settle floor is the spec's 0.70s")
    func defaultDelayIsSettleFloor() {
        #expect(ReceiptSettleGate.defaultDelay == .milliseconds(700))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./Scripts/test.sh FlipcashTests/ReceiptSettleGateTests/defaultDelayIsSettleFloor`
Expected: FAIL to compile — "type 'ReceiptSettleGate' has no member 'defaultDelay'".

- [ ] **Step 3: Name the floor and raise it**

In `ReceiptSettleGate.swift`, add above `init`:

```swift
    /// How long a just-sent row's receipt is held back. A *floor*, not a timer: the mapping only
    /// shows a receipt once the message is both confirmed sent and no longer held, so the reveal
    /// lands at `max(this, server confirmation)`.
    static let defaultDelay: Duration = .milliseconds(700)
```

and change the initializer:

```swift
    init(delay: Duration = ReceiptSettleGate.defaultDelay) {
        self.delay = delay
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./Scripts/test.sh FlipcashTests/ReceiptSettleGateTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Controllers/ReceiptSettleGate.swift FlipcashTests/Chat/ReceiptSettleGateTests.swift
git commit -m "fix(chat): hold a new send's receipt for the spec's 0.70s floor"
```

---

### Task 12: The bottom bar's springs

**Files:**
- Modify: `Flipcash/Core/Screens/Conversation/ConversationBottomBar.swift:26,95`

- [ ] **Step 1: Route both springs through the vocabulary**

Line 26:

```swift
/// Single spring driving the whole bar: the button morph, the composer's
/// appearance when the chat materializes, and the send-arrow pop.
private let barMorphSpring = ChatMotion.swap.animation
```

Line 95, inside `ConversationComposer`:

```swift
    /// Send button scale-in/out as text appears/clears.
    private static let sendButtonSpring = ChatMotion.sendButton.animation
```

`FlipcashUI` is already imported at line 10, so `ChatMotion` resolves.

Nothing else in this file changes. The composer's `.transition(.opacity)` (line 66) and the send arrow's `.transition(.scale(scale: 0.6).combined(with: .opacity))` (line 121) already match the spec, and there is no action-bar group to give `swapScale` to — `SendCashMorphButton` is one persistent view that morphs rather than two groups that swap.

- [ ] **Step 2: Build to confirm it compiles**

Run: `mcp__XcodeBuildMCP__build_sim`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Flipcash/Core/Screens/Conversation/ConversationBottomBar.swift
git commit -m "feat(chat): retune the bottom bar's morph to the shared vocabulary"
```

---

### Task 13: The motion sandbox preview

Fast iteration on feel without a server round-trip, and the place the Task 7 batch-update question gets settled.

**Files:**
- Modify: `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift:538-566`

- [ ] **Step 1: Add the scripted preview**

Below the existing `#Preview("Transcript")` (line 538), add:

```swift
/// Scripts the send moment end to end against a real controller: a bubble arrives, the receipt
/// settles in after the floor, then Delivered swaps to Read. Loops, so the same beat can be watched
/// over and over while a spring is being tuned.
#Preview("Motion — send → Delivered → Read") {
    let controller = ChatViewController()
    let base = ChatMessage.previewConversation(count: 8)
    controller.update(items: base.map { .message($0) }, animated: false)

    Task { @MainActor in
        while !Task.isCancelled {
            let sent = ChatMessage(id: "motion-send", text: "Sent just now", sender: .me,
                                   isContinuationFromPrevious: true)
            func push(_ last: ChatMessage) {
                controller.update(items: base.map { .message($0) } + [.message(last)])
            }

            try? await Task.sleep(for: .seconds(1))
            push(sent)                                                            // the insert
            // Mirrors ReceiptSettleGate.defaultDelay, which lives in the app target and isn't
            // reachable from here.
            try? await Task.sleep(for: .milliseconds(700))
            push(ChatMessage(id: sent.id, text: "Sent just now", sender: .me,
                             isContinuationFromPrevious: true, receipt: .delivered))
            try? await Task.sleep(for: .seconds(1.4))
            push(ChatMessage(id: sent.id, text: "Sent just now", sender: .me,
                             isContinuationFromPrevious: true, receipt: .read(time: "3:42 PM")))
            try? await Task.sleep(for: .seconds(2))
            controller.update(items: base.map { .message($0) }, animated: false)  // reset and loop
        }
    }
    return controller
}
```

- [ ] **Step 2: Open the preview and watch it**

Open `FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift` in Xcode and run the "Motion — send → Delivered → Read" preview. Watch specifically:

1. Does the bubble grow out of the **trailing** edge, or out of its centre? (Task 7 Step 1.)
2. Does the insertion **bounce**, or does it ease? An ease means the Task 7 Step 2 wrap didn't take — apply the fallback recorded there.
3. Does "Delivered" scale in rather than pop?
4. Does "Delivered"→"Read" swap in place, without the line jumping?

- [ ] **Step 3: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift
git commit -m "test(chat): add a scripted preview of the send moment"
```

---

### Task 14: The "after" recording and the gate

**Files:** none (artifacts only)

- [ ] **Step 1: Run every suite this change touched**

Run: `./Scripts/test.sh FlipcashTests/ChatMotionTests FlipcashTests/ChatReceiptTests FlipcashTests/ChatReceiptViewTests FlipcashTests/ChatMessageMappingTests FlipcashTests/ChatViewControllerTests FlipcashTests/ChatChangesetFlatteningTests FlipcashTests/ChatTranscriptDiffFuzzTests FlipcashTests/ChatBubbleViewCornerTests FlipcashTests/ChatMessageCellAlignmentTests FlipcashTests/LinkableBubbleViewTests FlipcashTests/ChatLinkMessageCellTests FlipcashTests/ChatCashCardSizingTests FlipcashTests/ReceiptSettleGateTests FlipcashTests/ChatMessageCopyTests FlipcashTests/ConversationReceiptWiringTests FlipcashTests/ConversationReceiptReporterTests`
Expected: PASS, all suites.

Do **not** run the full `AllTargets` plan — that's the user's job.

- [ ] **Step 2: Record the same sequence as Task 0**

Build and run on the simulator, then record the identical script — open a conversation, send, Delivered appears, counterpart reads — at 1x and again under Slow Animations.

Save as `~/Downloads/messenger-motion-after-1x.mp4` and `~/Downloads/messenger-motion-after-slow.mp4`.

- [ ] **Step 3: Confirm all four recordings exist**

Run: `ls -la ~/Downloads/messenger-motion-*.mp4`
Expected: four files — before/after × 1x/slow.

- [ ] **Step 4: Open the PR with the recordings attached**

```bash
gh pr create --assignee @me --base main --title "feat(chat): align the messenger's send and receipt motion to the prototype"
```

The body should cover: what moved (the nine divergences from the design doc's table), the three things that already matched and were left alone, the two §9 values that are design calls for Ted (grouped radius 6→4, receipt 12pt→11pt), and whether the Task 7 batch-update wrap took or fell back. Attach the four recordings. Per the user's standing preferences: no Verification section, no Figma links (cite node ids), no Claude attribution.

---

## Verification

Three layers, each with a different job.

**Unit tests — over what is genuinely deterministic.**

| Suite | Covers |
|---|---|
| `ChatMotionTests` | All eight springs against the spec's published mass-1 physics; the `CASpringAnimation` derivation; the insertion geometry, both directions and the no-sender case. |
| `ChatReceiptTests` | The receipt state's copy and its status/time split. |
| `ChatReceiptViewTests` | The state machine: entry, in-place swap, failure colour, idempotent re-apply, instant clear. |
| `ReceiptSettleGateTests` | The 0.70s floor. |
| The eight migrated suites | That the type change is behaviour-preserving. `ChatTranscriptDiffFuzzTests` in particular guards the batch update after the Task 7 wrap. |

**The sandbox preview**, for iterating on feel in seconds. It also settles the batch-update question rather than leaving it to argument.

**The before/after recordings**, at 1x and under Slow Animations. Only these can answer whether it feels like the proto, and that call belongs to the people who tuned it. The first two layers exist so the recordings are the only thing left to judge.

## Risks

- **Task 3 is the churn.** It touches the mapping layer that `ChatMessageMappingTests` covers heavily and eight test files besides. It's the most likely source of a regression that has nothing to do with animation. It is deliberately one commit so it can be reverted as one.
- **The batch-update wrap may not take.** DifferenceKit's staged updates may not inherit the outer timing. The fallback is written into Task 7 Step 2; the sandbox decides.
- **§9's two values are Ted's call.** Grouped radius 4 against the shipped 6, and receipt 11pt against the shipped 12pt, are visual design, not motion. The prototype isn't automatically authoritative over shipped design and the Figma page for this work is empty. They ship in the branch and get raised before merge.
- **Springs interact with self-sizing.** ChatLayout places rows from an estimate before cells self-size; a bouncier insertion overlapping a re-anchor could read as a wobble. The deferred re-scroll after the Delivered reveal is the existing mitigation and stays.
