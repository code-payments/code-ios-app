# Messenger motion alignment

Porting the tuned Montreal prototype's conversation animations into the shipped app, from
`Messenger Motion Spec.md`. The spec was extracted from a SwiftUI prototype; the shipped
transcript is UIKit, so most of it needs translating rather than copying.

**Status:** design approved, implementation not started.

---

## The problem the spec doesn't know about

The spec's source of truth is `FlipcashPrototype/Flows/Conversation/`, a SwiftUI target. It
prescribes `.transition`, `.animation(value:)`, `withAnimation`, `keyframeAnimator`, and
`ScrollViewProxy.scrollTo`, and its §10 gotchas are all about SwiftUI's commit model.

The shipped transcript is none of that. `ConversationScreen` hosts `ChatScreenRepresentable`,
which wraps `ChatViewController` — a `CollectionViewChatLayout` collection view diffed by
DifferenceKit ([`ChatViewController.swift`](../../FlipcashUI/Sources/FlipcashUI/Chat/ChatViewController.swift)).
Only the bottom bar is real SwiftUI.

So §10's gotchas mostly don't transfer. "Never wrap the model append in `withAnimation`" has no
analogue; ChatLayout's `keepContentOffsetAtBottomOnBatchUpdates` already solves the stale-geometry
problem that gotcha exists to prevent. "Corner radii only interpolate on explicit shape views" is
already satisfied — `BubbleBackgroundView` draws into `CAShapeLayer`s, which is the UIKit form of
doing it right.

One thing does transfer exactly. The project's iOS 18 minimum means
`UIView.animate(springDuration:bounce:)` is available, and it takes the *same* two parameters as
SwiftUI's `.spring(duration:bounce:)`. Every spring in the vocabulary ports with no conversion.

## Audit: what already matches

Three sections need no work, which narrows the change considerably.

| Section | Finding |
|---|---|
| §4 dot wave | Already exact. `ChatTypingIndicatorCell` carries all seven knobs at the spec's values (0.30 / 0.85 / 1.30 / 0.16 / 0.20 / 0.30 / 0.20), ported to `CAKeyframeAnimation` with cubic rise and fall. |
| §6 send arrow | Already exact. `ConversationBottomBar.sendButtonSpring` is 0.17 / 0.34 with scale 0.6. |
| §8 haptics | Already `.impact(weight: .light)` on incoming, none on send. The older copy the spec warns about was deleted in f1bf876e. |

§2's Delivered reveal is also closer than the spec assumes. `ReceiptSettleGate` already holds the
receipt for a delay and reveals it only once the message reaches `.sent`, which *is* the
`max(floor, server confirmation)` behaviour the spec's note asks for. The delay is 0.5s, not 0.70s.

## Audit: what diverges

| Section | Shipped | Spec |
|---|---|---|
| §2 delivered floor | 0.5s | 0.70s |
| §2 scroll | `UIView.animate(withDuration: 0.25)` | `scrollSpring` 0.30 / 0.12 |
| §2 insertion | ChatLayout default (`alpha = 0`) | `insertionSpring` + scale 0.95, anchored to the sender's edge |
| §3 Delivered→Read | One `UILabel`, text swapped under a 0.25s `transitionCrossDissolve` | Two overlaid labels, in-place scale cross-fade on `readSpring` |
| §5 corner morph | Absent; `shapeMask.path` is set in `layoutSubviews`, so it snaps | `cornerSpring` 0.45 / 0.32 |
| §5 grouped radius | 6pt | 4pt |
| §6 bar swap | `barMorphSpring` 0.35 / 0.2, action bar fades | `swapSpring` 0.27 / 0.31, action bar scales 0.95 + fades |
| §9 receipt type | 12pt medium | 11pt, status bold + time medium |
| §9 sender-flip gap | Uniform 8pt | 8pt, +6pt at a flip |

## Decisions

**Receipt state is structured, but stays single.** §3's in-place swap needs Delivered and Read as
distinct states; `ChatMessage.receipt` is a flat `String?` today, which cannot express it. It
becomes an enum.

The spec's *other* §3 proposal — a Read receipt persisting under the last-read message while a
newer one is unread — is out of scope. It is a behaviour change users would see, not a motion
change, and today's mapping deliberately shows a receipt only on `latestSentFromSelfID`.

That has a consequence worth stating plainly: with one receipt there is no second one to drop, so
the "layout collapse" that §3 gives `scrollSpring` to animate does not occur. The pinned
`readSpring` on the label swap still matters and is the point of the section. The outer
`scrollSpring` transaction largely does not. The nil→Delivered row growth from §2 is real and
still needs its deferred re-scroll.

**§9's values are implemented but flagged, not assumed.** Grouped radius 4 against the shipped 6,
and receipt 11pt against the shipped 12pt, are visual design changes rather than motion. The
prototype is not automatically authoritative over shipped design, and the Figma page for this work
is empty. Implement the spec's numbers, raise them with Ted before merge.

**Batch-update timing: wrap, with a fallback.** To spring the insertion, wrap
`collectionView.reload(using:)` in `UIView.animate(springDuration:bounce:)` so `performBatchUpdates`
inherits the timing. The risk is that DifferenceKit runs *staged* batch updates, and a multi-stage
changeset may not inherit cleanly. If it doesn't, fall back to setting scale and alpha in
`initialLayoutAttributesForInsertedItem` alone and accepting UIKit's default ease. Decide by
watching the sandbox, not by argument.

## Units

Each is independently reviewable; the numbered order is roughly the implementation order.

1. **`ChatMotion`** (new, `FlipcashUI/Chat/`) — the spring vocabulary as one source of truth. A
   `ChatSpring` value type over `(duration, bounce)` vending three forms: a SwiftUI `Animation`, a
   `UIView.animate(springDuration:bounce:)` call, and a `CASpringAnimation` for layer paths. Plus
   the eight named springs and five scale constants.
2. **Receipt state** — `ChatMessage.receipt: String?` becomes `ChatReceipt`
   (`.delivered` / `.read(String)` / `.failed(String)`). `ChatItem+Conversation` already produces
   all receipt copy in one layer, so it returns a case instead of a string.
3. **`ChatReceiptView`** (new) — replaces the bare `ChatReceiptLabel` inside `ChatColumnCell`. Two
   overlaid trailing-aligned labels. `nil→delivered` scales in from 0.95 on `deliveredSpring`;
   `delivered→read` cross-fades in place with 0.90 exit and enter scale on `readSpring`; removal is
   instant. It owns more than two pieces of state, so it is its own named unit rather than fields
   on the cell.
4. **Insertion attributes** — implement `initialLayoutAttributesForInsertedItem`: `alpha = 0`,
   `transform` scale 0.95, and `center` shifted by `(1 - 0.95) x width / 2` toward the sender's edge
   so the bubble grows out of its own side rather than its centre.
5. **Spring the scroll** — replace `scrollToBottom`'s fixed 0.25s curve with `scrollSpring`; add a
   keyboard-driven variant on zero-bounce `keyboardScrollSpring`.
6. **Corner morph** — `BubbleBackgroundView.apply` animates `shapeMask.path` and `borderLayer.path`
   with a `cornerSpring` `CASpringAnimation` when the radii change while the view is in a window.
7. **`ReceiptSettleGate` delay 0.5 → 0.70s.**
8. **Bottom bar** — `barMorphSpring` retuned to `swapSpring`; action bar gains scale-0.95 + opacity.
9. **§9 layout values** — grouped radius 6→4, receipt 12pt medium→11pt bold + medium, sender-flip
   +6pt via the `interItemSpacing` delegate.
10. **Motion sandbox `#Preview`** — scripts send → Delivered → Read against a real
    `ChatViewController`, extending the existing `ChatMessage.previewConversation` fixture.

## Verification

Motion cannot be asserted by a normal test, so the gate is three layers with different jobs.

**Unit tests, over what is genuinely deterministic.** The strongest is free: the spec's appendix
publishes derived physics for all eight springs (damping ratio, stiffness, damping), so that table
becomes a test fixture — assert `ChatSpring`'s `CASpringAnimation` derivation reproduces all eight
rows. Then the receipt state machine's transitions, the insertion-attribute geometry (an outgoing
insert shifts trailing, an incoming one leading), and the 0.70s floor. `ReceiptSettleGateTests` is
the precedent; extend rather than invent a pattern.

**Sandbox preview**, for iterating on feel in seconds without needing a real send against a server.
It also settles the batch-update fallback question above.

**Before/after screen recordings** via `record_sim_video` on a real send and a real Delivered→Read,
at 1x and under Slow Animations, attached to the PR.

Only the third layer can answer whether it feels like the proto, and that call belongs to the
people who tuned it. The first two exist so the recordings are the only thing left to judge.

## Risks

- **Unit 2 touches the mapping layer.** `ChatMessageMappingTests` covers `ChatItem.from` heavily.
  Changing the receipt type is churn beyond animation and is the most likely source of an
  unrelated regression.
- **The batch-update wrap may not take.** See the fallback above.
- **Springs interact with self-sizing.** ChatLayout positions rows from an estimate before cells
  self-size. A bouncier insertion overlapping a re-anchor could read as a wobble. The deferred
  re-scroll after the Delivered reveal (§10 gotcha 3) is the existing mitigation and stays.
