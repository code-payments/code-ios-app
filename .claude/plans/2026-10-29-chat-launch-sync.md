# Chat launch/resume churn

Branch `perf/chat-launch-sync`. Launch and resume redrew the chat list in a burst, even though the
notification extension had already persisted the pushed messages.

## Cause

1. `NotificationService.persist` wrote the newest three messages with `cursor: 0`, so the stored
   `catchupCursor` stayed where the app last left it. On foreground, `backfill(for:)` saw
   `latestEventSequence > cursor` for every pushed chat and ran `GetDelta` from the old cursor,
   re-fetching rows the extension had already written.
2. `writeMessage` skipped those rows, but `persist(operation:)` bumped `messageRevision` and ran
   `refreshFeedPreview` on every successful batch, changed or not.
3. `messageRevision` is global. `storedUnreadSeq` observes it and does a sync DB read, and
   `chatListProjection` calls that per unread chat from three readers (both lists and the tab
   badge), so every batch for any chat recomputed the whole list.
4. Growth over time: `conversation_member` had no index, and every member write deletes by
   `conversationId` before re-inserting, so each write scanned the whole table. Group member lists
   only grow (`mergedMembers` adds, never drops).

## Changes

- **B (147fb752a)** — the DB writers return whether a row changed; `messageRevision` and the
  preview refresh fire only then.
- **E (6d4df7853)** — the extension reads the stored cursor and runs `GetDelta` from it alongside
  the preview fetch, capped at 200 messages and 2 s. A delta that reaches its end writes its rows
  and advances the cursor to the head; anything else writes with `cursor: 0` as before.
  `persistCursor` is forward-only (via `persistMessages([], cursor:)`) so an in-flight app
  catch-up can't move the cursor back; the reset path still writes 0 directly.
  `reloadFromDatabase` re-seeds in-memory cursors from the store and bumps `messageRevision`
  unconditionally, which is what refreshes unread state for rows the extension wrote — B's gate
  never sees those rows.
- **A (633d067af)** — `CREATE INDEX IF NOT EXISTS` on `conversation_member(conversationId)`.
  No `schemaVersion` bump: the index changes nothing the store writes, `createTablesIfNeeded`
  runs on every open, and a bump would rebuild every store (one full re-sync) and make the
  extension skip every push until the next launch.

## Verified / not

- Tests: `ChatStoreWriteTests`, `DatabaseConversationsTests`, `ExtensionStoreTests`,
  `StoreMigrationTests`, `ConversationControllerTests` pass except the pre-existing
  `viewerStateCanInviteRoundTrip` (`ConversationRules` `CodingKeys` omit `canInvite`).
- The index test fails without the index (`SCAN conversation_member`).
- On a simulator: live and cold-start chat lists match; installing A over an existing store kept
  the same file and row counts and added the index.
- Not verified end to end: the extension's delta fetch. That needs a device with a real push —
  suspend the app, receive a message, resume, and check that no `delta-batch` persist runs for
  that chat.

## Left open

- C (per-conversation revision or cached `chatListProjection`) and D (scoped reload from the
  extension) — measure after B/E before doing either.
- `.versionMismatch` in the extension only leaves a breadcrumb.
- `receipts.countReceived` takes its baseline before the write, so extension-written rows are
  never counted as received.
