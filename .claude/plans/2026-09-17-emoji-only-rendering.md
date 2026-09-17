# Emoji-only messages render bare and large (2026-09-17)

A message whose whole body is one to three emoji renders as the emoji alone at
48pt — no bubble, no border, no wash — the way iMessage draws one. Everything
else about the row is unchanged: it keeps its side, its receipt line, its place
in the avatar gutter, tap-to-retry, swipe-to-reply and its context menu.

## What qualifies

`.text` content only, with no quote and no link, whose body is 1–3 emoji and
nothing else. A reply keeps its bubble because the quote panel lives inside the
bubble and has no standalone layout; a deleted tombstone and a cash card are
already different content and are never affected.

An edited emoji-only message does render bare. Its "Edited" marker moves out of
the bubble onto the metadata line beside the receipt (below).

## Detection

`EmojiOnlyDetector` in `FlipcashCore`, alongside `LinkDetector` and shaped the
same way: pure, synchronous, no state.

    public static func isEmojiOnly(_ text: String, limit: Int = 3) -> Bool

The rule, on grapheme clusters:

1. Trim leading and trailing whitespace and newlines.
2. Ignore whitespace clusters between the rest, so `👍 👍` qualifies.
3. Require 1...`limit` remaining clusters — bail on the fourth rather than
   walking a long message.
4. Every remaining cluster must be emoji: its first scalar has
   `properties.isEmoji`, and either that scalar has `properties.isEmojiPresentation`,
   or the cluster carries U+FE0F, or it is a regional-indicator pair, or it is a
   keycap sequence.

Clause 4 is what keeps `1`, `#` and `*` out — all three carry `isEmoji` but not
`isEmojiPresentation`, and a bare `unicodeScalars.count > 1` test would also
admit a letter with a combining mark. ZWJ families, skin-tone modifiers, flags
and keycaps all pass.

## Model: attribution and bubble grouping split apart

Today `isContinuationFromPrevious` / `isContinuedByNext` do two jobs at once:
they decide the author name and gutter face (`ChatColumnCell.updateAttribution`),
and they decide the flattened inner corner (`BubbleBackgroundView.radii`) and the
tight row gap (`ChatViewController.interItemSpacing`).

A bare emoji row splits those two jobs apart, because it should break the *bubble*
run without touching attribution:

- **Bubble grouping breaks.** A bubble stacked above a bare emoji would otherwise
  flatten its inner corner from 12 to 4 and take the 5pt tight gap — pointing at
  a bubble that is not there.
- **Attribution does not.** The author name still appears above an emoji that
  opens a run, and the run's single face still sits on whichever row closes it,
  emoji or not. A run of `[text, 👍]` puts the face beside the 👍.

So `ChatMessage` gains three stored properties, all decided at map time the way
`linkPreview` already is:

| Property | Job |
|---|---|
| `isEmojiOnly` | The body is 1–3 emoji and nothing else. |
| `joinsBubbleAbove` | The inner top corner flattens; the row above takes the tight gap. |
| `joinsBubbleBelow` | The inner bottom corner flattens; this row takes the tight gap. |

`isContinuationFromPrevious` / `isContinuedByNext` keep their names and their
values — they are the author run, which is what the mapper already computes — and
their doc comments are corrected to stop claiming they drive corners and spacing.

The mapper (`ChatItem+Conversation.swift`) computes the bubble pair from the
author pair:

    joinsBubbleAbove = groupedAbove && !rendersBare(current) && !rendersBare(previous)
    joinsBubbleBelow = groupedBelow && !rendersBare(current) && !rendersBare(next)

`rendersBare` is one local predicate over the raw message — text content, no
`repliedTo`, `EmojiOnlyDetector.isEmojiOnly` — applied to the row and both
neighbours, so there is a single place that decides what counts.

Consumers change in three places, each a flag swap: `BubbleBackgroundView.radii`
callers in `ChatBubbleView`, `LinkableBubbleView` and `ChatCashCardCell`, and the
`isContinuedByNext` read in `interItemSpacing`. A broken run there returns `nil`,
the same branch a grouping-window break already takes, so the gap behaviour needs
no new constant.

`ChatMessage.rendersAsLargeEmoji` is computed, not stored: `isEmojiOnly` and
`.text` content and `quote == nil` and `linkPreview == nil`.

## Cell selection

`ChatItem.cellReuseIdentifier` returns `ChatEmojiMessageCell.reuseIdentifier` for
a row where `rendersAsLargeEmoji` holds. That identifier is already folded into
`differenceIdentifier`, so editing a message into or out of emoji-only diffs as
delete-plus-insert rather than an in-place reconfigure — the rule the transcript
already applies to text↔cash and to a link gained or lost. UIKit forbids
reconfiguring an item into a different cell class, and `ChatTranscriptDiffFuzzTests`
already asserts the dequeued class matches the identifier.

## `ChatEmojiMessageCell: ChatColumnCell`

A `UILabel` at 48pt, one line, no background and no horizontal inset, so the
emoji starts where the bubble's outer edge would. 4pt of vertical padding keeps
the transcript's rhythm. Subclassing `ChatColumnCell` carries the receipt,
tap-to-retry, the avatar gutter and swipe-to-reply across unchanged.

It conforms to `BubbleCarrying`, which is what keeps the context-menu lift, the
edit spotlight (`ChatScreenViewController.refreshEditSpotlight` reads
`bubbleFrame` and `bubbleSnapshot`) and the quote-jump flash working.
`liftPreviewMaskingPath` is `nil` and no shadow is raised: a bare emoji lifts as
itself, and `BubbleBackgroundView.raise` on a clear layer casts nothing anyway.

The label is still capped at the cell's `maxWidth`, which three 48pt emoji come
nowhere near — the cap is there so a detector bug cannot produce an unbounded row.

## "Edited" on the metadata line

`ChatColumnCell`'s bottom slot becomes a horizontal metadata row holding an
"Edited" label and the existing `ChatReceiptView`. On a trailing-aligned `.me`
row that puts "Edited" to the left of "Delivered"; on an incoming row it sits
alone, since a receipt only ever rides the viewer's own latest sent message or a
failed send.

The label is hidden by default and only `ChatEmojiMessageCell` asks for it. Every
other cell keeps `EditedMarker`'s in-bubble placement untouched. It uses
`EditedMarker.font` and `.color`, which are already the receipt line's type and
tint, so the two pieces read as one line.

Two things the row has to preserve:

- **Implicit animation suppression.** `ChatReceiptView` overrides
  `action(for:forKey:)` to return `NSNull()` for `position` and `bounds`, because
  a receipt revealed inside a batch update otherwise springs in from the stack's
  origin and slides down across the bubble. Nesting it one level deeper means the
  new metadata row needs the same override, or showing and hiding "Edited" will
  drag the Delivered→Read swap sideways.
- **Collapsing.** The metadata row hides itself when both children are hidden,
  otherwise the column's 4pt spacing leaves a gap under every row that carries
  neither.

## Attention flash

`BubbleCarrying.flashAttention` today runs a keyframe on
`BubbleBackgroundView`'s wash layer, and a bare emoji row has no wash. The
keyframe builder moves to `ChatMotion` — where the rest of the transcript's
motion vocabulary already lives — and the emoji cell gets its own rounded layer
carrying the same white-0.10 lift.

It deliberately does not reuse `BubbleBackgroundView`. That view composites its
wash over an opaque `backgroundMain` base, on purpose, so a bubble renders the
same under the context menu's dim and the edit blur. Behind a bare emoji the same
opaque base would show as a rectangular patch against both.

## What does not change

- Grouping input: runs are still computed by author, with the same window and the
  same date-separator rule. Only what the bubble does with the result changes.
- The avatar gutter is still held open for every incoming row of a group
  transcript, so a bare emoji lines up with the bubbles above and below it.
- Cash cards, tombstones, link rows and replies render exactly as they do now.

## Tests

- `EmojiOnlyDetectorTests`: 1, 2 and 3 emoji pass and 4 fails; emoji plus text
  fails; ZWJ family, skin tone, flag and keycap pass; `1`, `#`, `*` and a letter
  with a combining mark fail; whitespace-separated emoji pass; empty and
  whitespace-only fail.
- `cellReuseIdentifier` mapping: a qualifying row picks the emoji cell; a reply,
  a link row and a tombstone with an emoji body all keep the bubble.
- Mapper: an emoji row clears `joinsBubbleAbove`/`joinsBubbleBelow` on itself and
  on both neighbours, while leaving `isContinuationFromPrevious` /
  `isContinuedByNext` alone — the split is the part most likely to regress.
- Cell: no bubble background, the label's font size, and the "Edited" marker
  landing on the metadata line rather than inside the content view.

## Risks

- **Notification preview cache.** `ChatMessage` is `Codable` and
  `NotificationPreviewCache` writes `[ChatItem]` as JSON into the App Group.
  Swift's synthesized decoder does not apply default values for missing keys, so
  a cache written by the previous build fails to decode once the three properties
  land. The read is `try?` and a miss falls back to a live fetch, which is what
  that cache is documented to do, so the cost is one slower notification expand
  per conversation.
- **The metadata row is the riskiest edit**, because it moves a view whose
  animation behaviour is load-bearing and shared by every cell in the transcript.
  The receipt's reveal and Delivered→Read swap should be checked on an ordinary
  text row, not just on an emoji one.
