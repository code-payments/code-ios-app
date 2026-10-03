# Persist pending chat photo sends

## Problem

A pending photo send lives only in memory. That's `ConversationController.pendingMediaChips` (`ComposerChip`, holding a `UIImage`) plus the in-memory `ConversationStore.pendingByConversation` row. If iOS kills the app in the background, the photo and its bubble are both lost.

On-device evidence, 2026-10-03 15:39–15:45:
- blob `51993f1f…` was reserved,
- the app was backgrounded 3 s later,
- the next log line is a cold launch at 15:45:07,
- the chat showed no photo and no failed bubble.

## What Android does (text only — Android has no media send)

- Pending rows are stored in the same Room table as messages, with status `SENDING`/`SENT`/`FAILED`.
- At login, every `SENDING` row is marked `FAILED`, and the user taps retry.
- A retry reuses the same client id, and the server dedupes on `client_message_id`.

## Design

### Storage
- Use a JSON manifest plus one JPEG file per photo, following `ChatDraftStore`'s precedent and reasoning.
- `FlipcashStore` (SQLite) is the wrong home because its versioning is destructive, and an outbox can't be re-fetched.
- Location: Application Support, scoped to the owner:
  - manifest `flipcash-<owner>-pending-media.json`,
  - photos in `flipcash-<owner>-pending-media/<clientMessageID>.jpg`.
- Leave the files at the default protection class, `completeUntilFirstUserAuthentication`.

### Entry
Each entry holds:
- `clientMessageID`
- `conversationID`
- `createdAt`
- the image file name
- `caption?` and `replyTo?`, exactly as `ChatMediaSendPlan` assigned them to this message
- `stored: UploadedPhoto?`

`stored` is set the moment `store` returns. `SealedPhoto` is metadata only (blob id, MIME type, size, dimensions, blurhash), so it's safe to persist, and it needs `Codable`.

### Encode once
- Encode the JPEG before the upload starts and write it to disk then. A kill mid-upload must not lose the photo.
- The upload then sends those same bytes. The retry path never re-encodes a re-decoded image.

### Lifecycle
- Write the entry when `sendMedia` runs. Attached-but-unsent composer chips are not persisted.
- Update `stored` when the bytes land.
- Delete the entry and its file at the same point `dropPending` runs: after `upsertConversationMessages` succeeds, never before.
- Also delete when the user discards a failed row, and when the failure can't be retried (`.rejected`).

### Launch
In `ConversationController.start()`, after hydrate:
- Load the manifest.
- Sweep orphans: files without an entry, and entries without a file.
- Re-insert each entry as a pending row, anchored by its `createdAt` rather than `newestMessageID`, and rebuild its chip from the file.
- `stored == nil`: show the row as failed with retry, as Android does. Retry uploads the file.
- `stored != nil`: resume the READY poll automatically, then send.

### Dedupe
- The risk is a kill after `sendMediaMessage` succeeds but before the entry is deleted.
- Before re-inserting an entry that has `stored`, look for a self-authored media message with that blob id in the loaded messages. If one exists, the photo already sent, so drop the entry.
- An entry with no blob id can't exist on the server, so it's always safe to re-insert.

## Tests
- The store round-trips its entries and sweeps orphans.
- Reconciliation drops an entry whose blob id is in the loaded messages and keeps one whose blob id isn't.
- At launch, `stored == nil` comes back as failed and `stored != nil` resumes.

## Known gaps
- An end-to-end encrypted photo sits as a plaintext JPEG in the app's sandbox until it sends.
- `pendingMatch`'s date window: a resumed send's row keeps its old `createdAt`, so the stream echo may not match it. The send RPC's own confirm still removes the row.
