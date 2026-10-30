# Chat message pinning UI (iOS) — plan

Brief: pins state + C1/C2/C6/C6b/C7/L1/L1b/L1c. Design note + frames under
`~/.t3-desktop/worktrees/code/t3-d75e595b/` (docs/superpowers/specs/2026-10-29-chat-message-pinning-design.md,
.claude/state/design/chat-pinning/).

## PR1 `feat/chat-pins-state`
- FlipcashCore `PinnedMessages` (pure struct): pins newest-first + version; `apply(change:summary:)`
  -> .applied / .needsRefetch / .stale; `visible` drops tombstones + nil messages; `markDeleted`.
- FlipcashCore `MessageCapability` gains `.pin` / `.unpin`; `resolve` takes `canPin` (viewerState) +
  `isPinned`; hidden on system/tombstone/encrypted/paymentRequest/unconfirmed own.
- App `ConversationPins` (@MainActor @Observable, `let pins` on ConversationController): per-chat
  `PinnedMessages`, load on open, apply PinsChanged, pin/unpin (TOO_MANY_PINS -> .full), pending
  pin after full, bumps messageRevision on change.
- `EncryptedChatClient`: getPinnedMessages / pin / unpin wrappers open sealed messages; opened()
  opens pinSummary.latest; .pinsChanged(.pinned) opened.
- Pure slot rule `PinSlot.resolve(hasPins:deckStyle:)` -> .bar / .toolbarButton / .none.

## PR2 `feat/chat-pins-ui` (stacked)
- PinBar (JoinRequestsAnchor shape, anchorGlass made internal), toolbar pin button, cycle cursor.
- Pinned sheet (.medium/.large), rows with real ChatBubbleView/cells, Unpin when canPin, L1b header.
- Strip swipe-up dock: drives PaymentRequestStripCollapse.progress; >0.5 completes (isPinned latch).
- Jump via ConversationScreen.land(on:) (pages + "Message Unavailable" dialog).

## Findings
- Strip cycle gesture is a DOWNWARD drag (PaymentRequestPill.cycleGesture), not horizontal as the
  brief says. Dock is upward drag on the same gesture.
