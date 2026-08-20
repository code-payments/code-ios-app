# Missing Convert (swap) activity rows — root cause

## Symptom

Swap/convert support shipped on the backend; no convert rows appear in the iOS
activity feed. Android shows them.

## Root cause

`flipcash.activity.v1.Notification.payment_amount` is **not populated for
multi-mint operations**. Upstream commit `0f97593` (flipcash2-protobuf-api #82)
added `swapped_crypto = 14` and, in the *same* commit, added this note to
`payment_amount`:

> Note: For multi-mint operations, amounts are carried in additional_metadata
> (eg. swapped_crypto).

iOS treats `payment_amount` as mandatory:

- `Activity.init(_:)` — `exchangedFiat: try ExchangedFiat(proto.paymentAmount)`
- `ExchangedFiat.init(_ proto: Flipcash_Common_V1_CryptoPaymentAmount)` throws
  `CurrencyCode.Error.notFound` on the empty `currency` of a proto3 default
  message, before that `KeyError.invalidKey` on the 0-byte mint.

So every `swapped_crypto` notification throws during mapping, and
`ActivityService` drops it:

```swift
let activities = response.notifications.compactMap {
    do { return try Activity($0) }
    catch { logger.error("Failed to parse activity", ...); return nil }
}
```

The row never reaches the database, so it is absent from both the per-mint
history and the cross-mint recent list.

Android is immune — it models the field as optional:

```kotlin
amount = from.paymentAmountOrNull?.let { localFiatOf(it) },   // nullable
```

## Fix

Resolve the display amount from the metadata when `payment_amount` is absent,
falling back to the swap's source (`from`) leg — which is exactly what
`SwapMetadata.fromFiat` documents as "the amount the row displays".

## Not the cause (ruled out)

- **User-agent gate.** The build reports `Flipcash/iOS/2026.8.2`
  (`CFBundleShortVersionString` 2026.8.2, build 272).
  `UserAgentClientInterceptor` is registered on every client, and neither
  grpc-swift-2 2.4.x nor grpc-swift-nio-transport sets a user-agent of its own,
  so the header reaches the wire unmodified.
- **Proto drift.** `activity/v1/model.proto` is byte-identical (modulo
  language `option` lines) to Android's vendored copy and to upstream HEAD.
- **Rendering.** `ActivityRow` already handles `.swapped` (overlapping from/to
  coin avatars, `fromFiat` over a `-fee Fee` subtitle).
- **Kind/metadata mapping.** `Activity.Kind.swapped` and
  `Activity.SwapMetadata.init` both map `swapped_crypto` correctly — they are
  simply never reached, because the amount is parsed first.

## Why tests didn't catch it

Every case in `ActivityProtoMappingTests` calls
`proto.paymentAmount = Self.basePaymentAmount()`. No case covered an unset
`payment_amount`.

## Related defects found (not fixed here)

1. `Activity.Metadata.init` returns `nil` for `.withdrewCrypto`, dropping the
   new `WithdrewCryptoNotificationMetadata.swap_metadata`. Android maps it.
2. `Database+Activities.getActivities(mint:)` filters `WHERE a.mint = ?` against
   the payment-amount-derived mint, so a two-mint swap can only ever appear in
   one token's history (the source token, after this fix).
3. `Database+Activities.makeActivity` force-unwraps
   `Activity.Kind(rawValue: row[a.kind])!` — a future server-side kind
   persisted by a newer build would crash an older one.
4. `HistoryController.syncHistory` advances its paging cursor from
   `activities.last?.id` *after* the drop-on-parse-failure `compactMap`, so a
   trailing unparseable notification silently rewinds/stalls the cursor.

---

## Second, currently-dominant cause: the server 500s on `GetPagedNotifications`

Found after installing the fixed build on a logged-in simulator. The client-side
mapping fix above is necessary but **not sufficient** — history sync is dead
before parsing is ever reached.

`ActivityService` swallowed the RPC error detail, so this was invisible. Added
structured logging on the `RPCError` catch, which produced:

```
flipcash.activity-service Transaction history RPC failed cause=nil code=internalError message=
flipcash.history-controller Sync failed error=unknown
```

Deterministic: 3 attempts per launch, 2 launches, always the same cursor
(`FdBo…WVfs`), always gRPC `INTERNAL`.

`cause=nil` with an empty `message` means this is a **status returned by the
server**, not a client-side deserialization failure — grpc-swift-2 populates
`message`/`cause` when it fails to decode a response itself.

Every other RPC on the same channel and auth succeeds in the same launch
(settings, user flags, profiles, event stream, phone linking), so this is not
connectivity, auth, or transport.

**Consequence:** no new activity of *any* kind has been ingested since that
cursor — the local DB still holds 1427 rows, kinds `1,2,3,4,5,8,9`, zero kind 10
(`swapped`), newest entries still the deprecated `bought`/`sold` pairs.

### Root cause: the swap migration orphaned the stored paging cursor

Confirmed by the user: **transactions older than today were dropped as part of
the migration/deploy that added swap support.**

That closes the chain:

1. The migration deleted historical notifications server-side.
2. iOS persists a paging cursor that *is* a notification id —
   `HistoryController.syncDeltaHistory` reads `database.getLatestActivityID()`
   and passes it as `query_options.paging_token`.
3. That id now names a deleted notification. The server cannot resolve the
   token and fails the request with `INTERNAL` rather than ignoring it.
4. `syncDeltaHistory` had **no recovery** — it always started from the stored
   cursor, so every subsequent sync failed identically and *no* activity of any
   kind was ever ingested again, the new convert rows included.

This is why the mapping fix alone changed nothing: the swap notifications never
reached the parser.

### Why Android is immune

Android never depends on a stored id staying resolvable:

- `FeedRemoteMediator` uses `loadKey = null` for `LoadType.REFRESH` and calls
  `dataSource.clear()` on that path — a refresh re-seeds from the top.
- `ActivityFeedCoordinator.fetchSinceLatest` falls back to
  `descending = latest == null`, i.e. it re-seeds when there is no local latest.

So a dropped cursor costs Android one refresh; on iOS it was terminal.

### Fix

`ErrorFetchTransactionHistory.warrantsFullResync` classifies server-side
failures (`.unknown`, `.rejected`) as recoverable-by-restart, and
`HistoryController.syncDeltaHistory` catches those and retries the whole sync
with no cursor. Transport failures and cancellation deliberately do *not*
trigger a full refetch — those are transient and refetching all of history
would be wasteful.

### Stale local rows: `SQLiteVersion` bumped 32 → 33

The activity table is upsert-only — `Database+Activities.insertActivity` writes
with `onConflictOf: table.id`, and the table has no delete path at all (unlike
conversations, blocklist, and contact sync). Sync can add and update rows by id
but can never learn that a row was removed server-side.

So a resync alone would insert the server's current history *alongside* the
~1427 pre-migration rows already stored, and those would linger forever as
rows for transactions the backend no longer has — an upgraded install showing a
longer history than a fresh install of the same account.

Bumping `SQLiteVersion` is the codebase's existing remedy for exactly this:
`SessionAuthenticator.initializeDatabase` deletes the store and rebuilds from
the server whenever the plist value exceeds the stored user version ("Currently
we don't do migrations so every time the user version is outdated, we'll
rebuild the database during sync"). Cost is a full re-sync on first launch
after upgrade.

### Also ruled out this session

- **User-agent version gate.** Both platforms send `2026.8.2`
  (Android `Packaging.kt`: `majorVersion = 2026, minorVersion = 8,
  patchVersion = 2`). Only the platform token differs (`iOS` vs `Android`).
- **Request shape.** Android's `asQueryOptions()` builds the same
  order + pageSize + pagingToken triple. Page size differs (iOS 1024 vs
  Android ≤100) but that was not the explanation.
