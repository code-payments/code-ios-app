# Persistence

Three storage layers with a strict division of labour: **SQLite** holds all cached server data, **Keychain** holds secrets, **UserDefaults** holds preferences and small flags. There are no migrations — a schema change deletes and rebuilds the database from the server.

```mermaid
graph LR
    BE["Server response"] --> Svc["Service"]
    Svc -->|upsert in transaction| DB["SQLite — writer, WAL"]
    DB -->|databaseDidChange| Upd["Updateable&lt;T&gt;"]
    Upd -->|re-query on MainActor| View["SwiftUI view"]
```

## Storage layers

| Layer | What lives here | Implementation |
|-------|-----------------|----------------|
| **SQLite** | All cached server data: balances, mint metadata, activity history, rates, verified proofs, limits, profile, user flags, contact-sync state, local contacts snapshot | `Database.swift` over the `dbart01/SQLite.swift` fork |
| **Keychain** | Secrets: current `UserAccount` (keypair), `historicalAccounts` (iCloud-synced) | `AccountManager` via a `@SecureCodable` wrapper |
| **UserDefaults** | Preferences/flags only: `wasLoggedIn`, `launchCount`, camera prefs, `balanceCurrency`, `recentCurrencies`, `localCurrencyAdded`, `storedTokenMint`, `betaFlags` | a custom `@Defaults` wrapper (the project does **not** use `@AppStorage`) |

> **Rule:** cached backend data → SQLite. UserDefaults is only for preferences and small local flags. Rates/balances/metadata/activities/limits all belong in SQLite.

## Database controller

`Flipcash/Core/Controllers/Database/Database.swift` — `nonisolated class … @unchecked Sendable` (not actor-isolated; Swift 6 sendability asserted manually). Opens **two connections**: a `writer` (WAL mode, foreign keys on, 10k-page cache) and a read-only `reader`, both with a 2s busy timeout. SQLite.swift serializes each connection through its own private queue.

- **`transaction(silent:_:)`** counts `totalChanges` and posts `.databaseDidChange` (coalesced) when rows actually changed. `silent: true` skips the notification for write-throughs with no UI listeners (e.g. verified-rate upserts).
- **Reactive reads**: `@Observable Updateable<T>` subscribes to `.databaseDidChange` and re-runs its query on `@MainActor`, giving views automatic refresh without polling.
- One database file per owner: `Application Support/flipcash-<owner.base58>.sqlite` (+ `-wal`/`-shm`) — multi-account safe. `Database` is a `SessionContainer` property injected by reference into Session, the controllers, and the cash operations.

## Schema

`Schema.swift` — all tables are `WITHOUT ROWID` (explicit primary key as the B-tree key):

| Table | Key | Stores |
|-------|-----|--------|
| `balance` | mint | Per-mint quark balance + cost basis |
| `mint` | mint | Full mint metadata (name, symbol, decimals, image, VM metadata, launchpad curve/vault/supply/fees, social links, bill colors, createdAt) |
| `activity` | id | Transaction history rows (kind, state, title, quarks, native amount, currency, mint, date) |
| `cashLinkMetadata` | id → activity (CASCADE) | Vault address + `canCancel` for cash-link activities |
| `limits` | 1 (singleton) | Serialized `Limits` proto |
| `rate` | currency | One JSON `Rate` per fiat (cold-launch rehydration) |
| `verified_rate` | currency | Raw signed `rateProto` per fiat |
| `verified_reserve` | mint | Raw signed `reserveProto` per launchpad mint |
| `profile` / `userFlags` | 1 (singleton) | Serialized blobs |
| `contact_sync_state` | 1 (singleton) | Sync cursor (checksum) |
| `flipcash_contact` | e164 | Numbers server-confirmed on Flipcash |
| `local_contacts_snapshot` | (e164, contactId) | Last uploaded contact set; `contactId` resolves name/avatar at render |

Custom `Value` conformances store `UInt64` as `Int64`, `PublicKey`/`Key32` as `Blob`, `CurrencyCode` as `String`.

## Query organization

Extension-per-concern, all `nonisolated extension Database`: `Database+Balance`, `+Activities`, `+Rates`, `+VerifiedProtos` (conforms `Database` to `VerifiedProtoStore`), `+Limits`, `+Profile`, `+ContactSync`. Each owns the reads/upserts for its domain.

Row models live in `Database/Models/`. Only two dedicated structs exist — `StoredBalance` (from the `balance JOIN mint` query, computes the USDF equivalent inline via the bonding curve) and `StoredMintMetadata` (converts to/from the domain `MintMetadata`). Singleton-row tables decode directly to their domain type inline; no separate model struct.

## Versioning & migrations — there are none

`SessionAuthenticator.initializeDatabase` version-gates the store:

1. Read persisted version from a companion text file `flipcash-<owner.base58>version`.
2. Read `SQLiteVersion` (an integer) from `Info.plist`.
3. If the Info.plist version is higher → delete the three SQLite files, write the new version.
4. Open a fresh `Database` (`createTablesIfNeeded()` runs in `init`).

> **Bump `SQLiteVersion` in Info.plist on every schema change** — adding/removing a table or column, or changing which table a query reads from when the old schema can't satisfy it. No migration code is needed, but **all data must be recoverable from the server**, because the local store is thrown away.

## The SQLite.swift fork

`github.com/dbart01/SQLite.swift` (pinned to `master`), forked off the official `0.15.4`. It adds:

1. **Upsert WHERE fix** — moves `whereClause` after `DO UPDATE SET` (the official repo puts it before `ON CONFLICT`, producing invalid SQL for filtered upserts like `table.filter(...).upsert(...)`). Load-bearing in `Database+Balance`.
2. **Custom `DispatchQueue` injection** — the fork *adds* a `queue:` parameter to `Connection.init` (upstream has none); the project currently omits it, so the default queue is used.
3. **Public `Setter` access (pending)** — to build `COALESCE(excluded.col, col)` ON CONFLICT clauses; until then a two-statement workaround is used.

Do not switch to the official repo without verifying filtered upserts still emit valid SQL.
