# Parallel-async sweep (2026-11-02)

Branch `perf/parallel-async`. Goal: run independent back-to-back awaits concurrently on hot paths.

Method: a script flagged adjacent same-indent `await` statements, near-adjacent awaits whose second
line doesn't use the first's result, and `for` loops awaiting per item (~140 hits across `Flipcash`,
`FlipcashCore`, `FlipcashUI`, `NotificationService`, `ShareExtension`). Each plausible hit was read
by hand. No `.refreshable` sites exist.

Isolation facts that shape the fixes:
- App target: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + `NONISOLATED_NONSENDING_BY_DEFAULT`.
  Child tasks that call main-actor methods still overlap, because each suspends inside the gRPC
  continuation.
- `FlipcashCore`: no default isolation, no upcoming features; nonisolated async runs off main.
- `Poller` awaits the whole action, so `async let` children finish before `waitUntilFinished()`
  returns (the background drain before `database.close()` holds).
- Bounded fan-out house pattern: `FlipBlocklisting.resolve` (window of 4, results by index).

## Fix

| # | Site | Independent because | Win |
|---|------|--------------------|-----|
| 1 | `Session.swift:627` poller: flags, limits, balance | Separate RPCs and tables; each already `try?`-isolated | First balance at launch no longer waits behind flags + limits round trips; every 10s tick and the background drain are shorter |
| 2 | `GroupSendViewModel.swift:233`, `ReactionBoostViewModel.swift:228` per-recipient `resolveUserID` | Read-only lookups; results kept in input order; first failure still fails the send | N serial round trips before a group send become ~N/4 |
| 3 | `CommunityChats.swift:211` mint metadata, community chats | `fetchCommunity(mint:)` doesn't read metadata; `CurrencyInfoScreen` already runs them in separate `.task`s | One round trip off screen open |
| 4 | `ChatProfileScreen.swift:260` avatar, cover, permissions after hydration | Each writes a different field; hydration stays first (avatar reads its picture) | Up to two round trips off profile open |
| 5 | `TipConversationsScreen.swift:411` `fetchIfMissing`, `loadSeal` | Same pair `PaymentRequests.refreshChat` already overlaps | One round trip per chat row with a request preview |
| 6 | `HostedLobbies.swift:65`, `TipConversationsScreen.swift:170`, `PaymentRequests.swift:251/279` per-item refreshes | Per-key writes; main actor serializes them | N round trips become ~N/4 |
| 7 | `ActivityAvatar.swift:194` counterparty, from-mint, to-mint | Disjoint fields | Small: mints are usually cached; the avatar download is the slow part |
| 8 | `ChatMediaUploader.swift:256` blurhash, encrypted upload | Blurhash reads the plaintext only; upload doesn't need it | Blurhash CPU time off every sealed photo send |

## Skip

- `KnownAuthorDirectory.resolve:139`: sequential by design (doc comment: avoids contending with the transcript load).
- `HistoryController.sync:109`: pending sync reads pending IDs the delta sync writes.
- `ConversationController.catchUpOpenChat:759`, `ConversationScreen.swift:1990`: `refreshReactions` reads message IDs `catchUp`/`loadMessages` write; `clearDeliveredNotifications` is cheap local IPC.
- `ConversationController.start:594`: ordering documented (stream before feed so live events aren't lost).
- `SessionAuthenticator.authenticate:458-464`: `createAccounts` requires the user to exist.
- `Session.unlinkProfile`: not hot; parallel unlinks change what's left on the server after a failure.
- `Session.buy(with:):837`: both metadata reads are DB hits in practice; buy path, ~0 win.
- Mint-name loops (`ChatProfileScreen:306`, `EditGroupScreen:76`, `ConversationScreen:1194`): N is almost always 1 and cached.
- `UserProfileScreen:284`: featured groups need the username `loadProfile` sets.
- `ConversationTyping.sendFinalStops`: fire-and-forget at sign-out.
- `ConversationScreen:681` host-request avatars: up to 3, and `ProfileAvatarStore` downloads are deduped; marginal.
- `InvitePeopleViewModel:70`, media send loops (`ConversationController:2589/2737`), `ShareModel:245/276`, `ContactListService:137`: message/stream order is the contract.
- `MessageLinkLookup`: the paired awaits are in-memory lookups.
- Retry loops (`RatesController`, `Client+Transaction`, `Client+Messaging`, `PushController`, `SendAmountViewModel:541`, `UsdcSweepOperation`): sequential by definition.
- Already concurrent: `loadFeeds`, `reconcileFeeds`, `backfillMessages`, `refetchAfterReconnect`, `refreshChat`, `fullConversations`, `NotificationService.fetchMemberNames`, `FlipBlocklisting.resolve`.

## Flag

- Nothing in signing or intent construction needed a change.
- `ChatProfileScreen` open can issue up to three `getChat` calls for one chat (hydration, cover, permissions). One fetch could serve all three; out of scope.

## Outcome

Commits (oldest first): 96cd27082 poller, e3c405108 recipients, 97997b39a currency info,
61f6ad2b4 chat profile, 414564243 tips row, ea3297011 lobby/request loops, 147bc4a10 activity,
19d55b5b5 blurhash.

Helpers added:
- `RecipientBatch.resolveOwners` (`SessionProtocols.swift`): bounded throwing fan-out, results in input order.
  A protocol extension calling `self.resolveUserID` from `@MainActor` child tasks failed region-isolation
  checking even with the extension marked `@MainActor`; taking a `@Sendable` closure that captures the
  (main-actor, so Sendable) view model works.
- `Collection.concurrentForEach(limit:)` (`Flipcash/Extensions`): bounded non-throwing fan-out for per-key refreshes.

Checks: `./Scripts/build.sh` clean; no warnings on touched files beyond five pre-existing ones in
`Session.swift` (none on the poller). `FlipcashTests` full target: 3590 passed.
