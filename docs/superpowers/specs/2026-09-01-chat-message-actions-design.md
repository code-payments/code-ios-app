# Chat message actions: reply, edit, delete

Design for adding reply, edit, and delete to the iOS conversation transcript. The UI
reference is WhatsApp. The structure has to survive the move to group chats with a
permissions model, which does not exist on the wire yet.

## What the contract already provides

No proto work is needed. The pinned `flipcash2-client-protocol` 0.2.0 already carries
everything:

| Contract element | Purpose here |
|---|---|
| `ReplyContent { replied_message_id, content }` | Reply, with a Text or Media body |
| `DeletedContent { deleted_ts, deleted_by }` | Tombstone; absent `deleted_by` means a system or moderation removal |
| `Message.last_edited_ts` | Drives an "edited" affordance; content is always materialized |
| `Message.event_sequence` | Per-message version stamp, advanced by every send, edit, and delete |
| `rpc EditMessage` / `rpc DeleteMessage` | Both require `expected_event_sequence`; both answer `OK / DENIED / MESSAGE_NOT_FOUND / CANNOT_EDIT\|CANNOT_DELETE / CONFLICT` |

Two constraints fall directly out of the contract and shape the client:

`EditMessageRequest.content` accepts TextContent, ReplyContent, or MediaContent, never
CashContent. Cash messages are structurally uneditable, so that is not a product choice
we get to make.

`expected_event_sequence` is validated `>= 1`. A message that has not been confirmed by
the server yet carries `eventSequence == 0`, so no valid edit or delete request can be
built for it.

The contract also carries `AddReaction`, `RemoveReaction`, and `GetReactors`. Reactions
are out of scope for this work, but the context menu leaves a slot for them.

## Decisions

**Delete is "for everyone" only.** That is the only delete the wire models: the server
replaces the content with a tombstone that every participant sees. A local "delete for
me" has no wire representation, would not follow the user to a second device, and would
not survive the schema-driven database rebuild. The delete action is still modelled as a
list of delete *kinds* so adding a local one later is a new case rather than a rewrite.

**Both tombstone presentations are built.** The transcript can render a deleted message
either as a placeholder bubble or as nothing at all, selected by a
`DeletedMessagePresentation` value passed into the mapper. `ChatItem.from` currently
filters tombstones out unconditionally
(`ChatItem+Conversation.swift:60`), so the hidden path already exists; the placeholder
path is new. Both get test coverage and the product decision can move later without a
code change.

**Cash and tip bubbles offer Reply only.** Edit is impossible per the contract. Delete
is excluded deliberately: tombstoning a cash message hides the record while the transfer
itself has already happened, which invites someone to delete a payment out of the
transcript and leave the money moved. Today these rows return no menu at all
(`ChatViewController.swift:519`); they will return a Reply-only menu.

**The edit window is a policy value, defaulting to none.** WhatsApp cuts editing off
after fifteen minutes. Our contract has `CANNOT_EDIT` but never documents what triggers
it, so a client-side window would be a guess: too long and we offer an action that
fails, too short and we hide one that would have worked. `MessagePolicy` carries an
optional `editWindow` that is `nil` today. If the backend documents a window it becomes a
constant.

**Reply is started from the context menu and from a swipe.** The swipe is the gesture
people actually reach for. Its cost is a pan recognizer that has to coexist with the
transcript's scrolling and the existing long-press lift; see the hazard noted under
Surfaces.

**Tapping a quote jumps to the original whenever it is in the local database.** The
transcript's window is a bounded slice of the *local* database rather than of the network,
and `loadOlderMessages` persists every page it fetches, so everything the user has
scrolled past stays on device. The jump is therefore one anchor move, not a paging loop:
`windowedMessages(for:startingAt:limit:)` with a `startID` reads every message from that id
forward (`ConversationController.swift:841`), so pointing the loader's anchor at the quoted
id brings it into the window with no loop and no network call. Only history that was never
fetched would need `GetMessages` in an unbounded loop, and that stays out of scope: there
the quote renders as unavailable and the tap does nothing. WhatsApp keeps the whole thread
on device and so never meets that case at all.

**Permissions are expressed as capabilities, not roles.** `Member` on the wire is
`{ user_id, user_profile, pointers }` with no role field, and the server only ever answers
`DENIED`, `CANNOT_EDIT`, or `CANNOT_DELETE`. Anything the client models here is
scaffolding the server overrules. Resolving a `Set<MessageCapability>` rather than a role
means the eventual role taxonomy becomes one more input to that resolution, and no call
site changes: the menu already asks what can be done to a message, not who the viewer is.

## Architecture

Three new units, three existing ones extended.

**`MessageCapabilities`** (new, `FlipcashCore`, pure)

```swift
func capabilities(
    for message: ConversationMessage,
    in conversation: Conversation,
    as selfUserID: UserID,
    policy: MessagePolicy
) -> Set<MessageCapability>
```

No I/O, no actor isolation, fully table-testable. `MessagePolicy` carries the optional
edit window.

**`ComposerMode`** (new, app, `@Observable`) owns `.new`, `.replying(to:)`, and
`.editing(_:)` along with the draft text. `ConversationBarModel` sheds `draft` and keeps
`isComposing` alone, so neither type holds more than two pieces of state.

**`ConversationController+MessageMutations`** (new file) holds `reply`, `edit`, and
`delete`. Each mirrors the existing `deliver`: apply optimistically, call the RPC,
reconcile. The file touches only `store`, `database`, `messagingService`, and
`selfUserID`.

**`ChatMessagingService`** gains `editMessage` and `deleteMessage` wrappers plus reply
content on send, each with an error enum in the existing `ErrorSendMessage` shape
conforming to `ServerError` and `TransportClassifiableError`.

**`ConversationMessage` and `ChatMessage`** gain the fields below.

**`ChatViewController` and `ChatBubbleView`** gain the menu, the swipe, the quote view,
and the placeholder style.

Every action follows the same path: menu or swipe, controller method, optimistic apply,
RPC, reconcile. Nothing new observes anything new.

## Models

A reply is a decoration on a text message, not a new content kind. The wire nests it, but
mirroring that nesting into `ConversationMessage.Content` would force every existing
`case .text` path (link detection, the mapper, the bubble) to learn a second shape. The
proto initializer unwraps it instead: the inner `TextContent` becomes `content`, and a
separate field carries the citation. The unwrap is total, because a reply body can only
be Text or Media, never Cash.

```swift
public let repliedTo: MessageID?   // nil for ordinary messages
public let lastEditedTs: Date?     // drives the "Edited" marker
case deleted(Deletion)             // was: case deleted
```

`Deletion { deletedBy: UserID?, deletedAt: Date }`. The author is needed to choose between
"You deleted this message" and "This message was deleted"; a nil author is a moderation
removal.

This also fixes a live defect. `ConversationMessage.init?(_:)` currently returns `nil` for
`.reply`, so reply messages sent from any other client are dropped from the transcript
today.

`ChatMessage` gains `quote: ChatQuote?`, `isEdited: Bool`, `actions:
[ChatMessageAction]`, and a `.deleted(String)` content case carrying resolved copy, which
keeps the cell rendering strings rather than deciding anything. `ChatQuote` holds a
display name, a snippet, a kind of `.text`, `.cash`, or `.unavailable`, and the target
`stableID`.

Persistence adds `repliedToId`, `lastEditedTs`, `deletedBy`, and `deletedAt` columns. A
reply stays `kind = 0`, since it is still a text row. The schema change requires bumping
`SQLiteVersion` in Info.plist.

## The mutation loop

`writeMessage` is strict last-writer-wins on `eventSequence`, and on an equal version it
keeps the stored row (`Database+Conversations.swift:346`). That rules out persisting an
optimistic edit. To write one we would have to invent a sequence: guess `+1`, and if the
server's real advance is also `+1` the confirmed copy is discarded on equality and our
text stands in place of whatever the server actually stored. A relaunch mid-flight would
then hydrate from the invented row.

So the database holds server truth only. Optimistic edits and deletes live in
`ConversationStore` as an overlay, the way `PendingEntry` already handles optimistic
sends, and `displayedMessages(for:over:)` composes them in one place. `ConversationStore`
is a `Sendable` struct, so this is all unit-testable without I/O.

```swift
struct MutationEntry {
    let messageID: MessageID
    let kind: Kind          // .edited(String) | .deleted
    let expectedSequence: UInt64
}
```

The overlay drops on a precise condition rather than a timer: a database row arrives for
that message with `eventSequence > expectedSequence`.

Per action:

- `OK`: persist the returned message, drop the overlay.
- `CONFLICT`: persist the current state the server returned, which out-versions ours, drop
  the overlay, and tell the user. No automatic retry. The conflict exists because another
  device won, so retrying without the user would clobber it.
- Transport failure: revert the overlay. A failed delete makes the message reappear, which
  is the truth.

Reply needs none of this. It is a send, using the same `ClientMessageId` idempotency and
the same pending overlay, with `ReplyContent` in place of `TextContent`.

`ErrorReporting.captureError` is called unconditionally per the hard rule. `reportingLevel`
is where `CONFLICT` and `CANNOT_EDIT` are classified as expected outcomes rather than
incidents, while `DENIED` reports.

Deleting the newest message has to fall the feed preview back to the previous visible one.
`setFeedPreview(_:in:force:)` already documents `force` as the escape hatch for exactly
that case.

## Surfaces

**Menu.** `ChatMessage` carries its resolved `actions`, matching its existing rule that
everything the cell needs to draw is already on it. `ChatItem.from` gains a
`capabilities:` closure parameter alongside the existing `cashBranding:` one, so the
mapper stays pure and the rules stay in `FlipcashCore`. `ChatViewController` gains one
callback, `onMessageAction: ((String, ChatMessageAction) -> Void)?`, rather than three.
The reactions strip later becomes an inline `.small` `UIMenu` in the first child slot.

**Swipe.** A `UIPanGestureRecognizer` on the collection view rather than per-cell, so cell
reuse cannot strand it. Horizontal only, translating the target cell up to roughly 64pt
with resistance, firing on release past a threshold, and refusing to begin while
`isShowingContextMenu` or `isUpdating`.

One specific hazard: `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` returns
`true` unconditionally today (`ChatViewController.swift:498`), which is deliberate for the
tap-to-dismiss recognizer. The reply pan must not run simultaneously with the scroll pan,
so that blanket `true` has to become discriminating. Getting it wrong scrolls the
transcript diagonally during a drag.

**Bubble.** `ChatBubbleView` is a single `UILabel` today. It gains an optional quote header
inside the bubble background (accent bar, name, one-line snippet) and the deleted
placeholder as a muted italic variant with no link detection and no tap.

The "Edited" marker cannot ride the receipt line, because the receipt attaches only to the
latest confirmed self message (`ChatItem+Conversation.swift:65`) and most edited messages
will not have one. It is a muted suffix inside the bubble instead.

**Composer.** `ComposerMode` drives a dismissible banner above the field. Entering
`.editing` pre-fills the field with the current text and turns send into a confirm.
Entering edit mode must stash the in-progress `.new` draft and restore it on cancel,
otherwise the user silently loses what they were typing.

**Scroll to quote.** `scrollToMessage(id:)` scrolls when the target is already rendered.
When it is persisted but outside the window, `MessageLoader` moves its anchor to the quoted
id first and the scroll follows the re-read. Anchoring far back reveals every row between
the target and the newest message at once, so it must ride the animation-suppressed
transaction `loadOlderMessages` already uses rather than playing an insertion per row. An
id that is in neither place no-ops.

## Capability rules

| Message | Capabilities |
|---|---|
| My own text, confirmed, within the edit window | `.copy`, `.reply`, `.edit`, `.delete` |
| My own text, confirmed, outside the window (when a window is configured) | `.copy`, `.reply`, `.delete` |
| My own text, unconfirmed (`eventSequence == 0`) | none |
| Another participant's text | `.copy`, `.reply` |
| Any cash or tip message | `.reply` |
| A tombstone | none |

The empty set for unconfirmed messages is not a style choice: `expected_event_sequence`
is validated `>= 1`, so no valid request can be built.

## Testing

Swift Testing throughout, per the hard rule.

Unit tests cover `MessageCapabilities` as a table over the rules above; the
`ConversationStore` mutation overlay (applies, drops only on a strictly higher
`eventSequence`, reverts on failure); `ChatItem.from` for quote mapping in all three quote
states, both deleted presentations, and the edited marker; `ConversationMessage.init?(_:)`
for the reply unwrap and both deletion shapes; a database round trip over the new columns
confirming the last-writer-wins comparison is unchanged; and `MessageLoader` revealing a
quoted id that sits in persisted history below the window, while leaving the anchor alone
for an id the database does not hold.

One regression deserves its own test. In placeholder mode tombstones stop being filtered
out, so they begin participating in date separators and same-sender grouping. The receipt
anchor at `ChatItem+Conversation.swift:65` selects `messages.last { isFromSelf && status
== .sent }`, which would now match a deleted row and strip the receipt off the last
visible bubble. Deleted messages must be excluded from that selection.

The gesture negotiation, the context menu lift, and scroll-to-quote are verified by hand.

## Path to extracting a mutations actor

An actor in `FlipcashCore` owning optimistic apply and conflict reconciliation is the
cleaner end state. It is not part of this work, because the expensive part is not the
mutation methods: `ConversationController` is `@MainActor @Observable` and the store is
its observable state, read by SwiftUI through `var conversations: [Conversation] { store.conversations }`.
Moving ownership into an actor means re-plumbing observation, and that cost does not shrink
however this feature is written.

What this design does is make every other step mechanical:

1. The three methods live in their own file with an explicit, visible dependency set.
2. The conflict decision is already a pure function in `FlipcashCore`, testable with no
   actor and no main actor.
3. A follow-up with no feature attached moves `send` and `deliver` into that file, so all
   four optimistic writes are colocated.
4. What remains is the store-ownership question, worth taking on when the store should
   leave the main actor for its own sake.

## Out of scope

Reactions, media replies, forwarding, starring, pinning, multi-select, and any role or
moderation capability beyond the seam that will accept one.
