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

## The bubble draws bare, rather than a second cell

`ChatBubbleView` already layers a `BubbleBackgroundView` under a *sibling* `UILabel` —
the label is not a child of the background, so the background's shape mask never clips
the text. A bare row is therefore the same view with its chrome switched off, not a new
cell.

`BubbleBackgroundView.apply` takes a `bare` flag. Bare clears the opaque `backgroundMain`
base and hides the wash and the hairline border; it keeps the shape mask and the
attention layer. Keeping the mask is what keeps the jump flash rounded — without it the
highlight would be a rectangle floating where no bubble is.

`ChatBubbleView.configure` reads `message.rendersAsLargeEmoji` and, when it holds, draws
the body at 48pt, drops the 12pt horizontal inset to 0 so the emoji starts where the
bubble's outer edge would, and tightens the 9pt vertical padding to 4pt. The label is
still capped at the cell's `maxWidth`, which three 48pt emoji come nowhere near — the cap
is there so a detector bug cannot produce an unbounded row.

`ChatMessageCell` keeps its `BubbleCarrying` conformance and returns `nil` from
`liftPreviewMaskingPath` for a bare row: the lift preview is not clipped to a bubble
shape, and `BubbleBackgroundView.raise` given no path leaves UIKit to derive the shadow
from the layer's contents, which for a clear layer is nothing. A bare emoji lifts as
itself.

Nothing about cell selection changes. `cellReuseIdentifier` is untouched, so editing a
message into or out of emoji-only stays an in-place reconfigure and the transcript's
diffing is not involved at all.

This is the shape Android shipped in `code-payments/code-android-app#1482`, where the
bare form lays out through the existing `Bubble` behind a `bare` flag for the same
reason it does here: the run's corner geometry, the width ceiling and the jump flash
stay in one place.

## "Edited" on the metadata line

`ChatColumnCell`'s bottom slot becomes a horizontal metadata row holding an
"Edited" label and the existing `ChatReceiptView`. On a trailing-aligned `.me`
row that puts "Edited" to the left of "Delivered"; on an incoming row it sits
alone, since a receipt only ever rides the viewer's own latest sent message or a
failed send.

The label is hidden by default, and `ChatMessageCell` asks for it only on a bare row.
Every other row keeps `EditedMarker`'s in-bubble placement untouched. It uses
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
- `rendersAsLargeEmoji`: a qualifying row renders bare; a reply, a link row and a
  tombstone with an emoji body all keep the bubble.
- Mapper: an emoji row clears `joinsBubbleAbove`/`joinsBubbleBelow` on itself and
  on both neighbours, while leaving `isContinuationFromPrevious` /
  `isContinuedByNext` alone — the split is the part most likely to regress.
- `ChatBubbleView`: a bare row draws no wash, no border and no opaque base, while an
  ordinary row still draws all three; the label's font size; and the "Edited" marker
  landing on the metadata line rather than inside the bubble.

## Risks

- **Notification preview cache.** `ChatMessage` is `Codable` and
  `NotificationPreviewCache` writes `[ChatItem]` as JSON into the App Group.
  Swift's synthesized decoder does not apply default values for missing keys, so
  a cache written by the previous build fails to decode once the three properties
  land. The read is `try?` and a miss falls back to a live fetch, which is what
  that cache is documented to do, so the cost is one slower notification expand
  per conversation.
- **Bare mode is a flag on the view every text bubble uses**, so a regression there
  reaches ordinary bubbles rather than staying inside an emoji-only cell. That is the
  cost of not isolating this in its own cell class; the mitigation is that the bare
  tests assert the non-bare row still draws its wash, border and base.
- **The metadata row is the riskiest edit**, because it moves a view whose
  animation behaviour is load-bearing and shared by every cell in the transcript.
  The receipt's reveal and Delivered→Read swap should be checked on an ordinary
  text row, not just on an emoji one.
