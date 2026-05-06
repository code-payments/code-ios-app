# Package Restructure Plan

**Date:** 2026-05-02
**Goal:** Mirror filesystem ↔ Xcode groups and split the three monolithic packages (`FlipcashCore`, `FlipcashUI`, `FlipcashAPI`) into thinner layered packages so we can adopt Swift 6 strict + per-package `@MainActor` defaults incrementally.
**Blocked by:** [`2026-05-02-legacy-app-deletion.md`](2026-05-02-legacy-app-deletion.md). Do not start any phase until the legacy-deletion PR is merged — the dep graph reasoning here assumes a single-app repo.
**Branches:** one per phase; see Sequencing.

---

## Revisions (2026-05-02 red-team)

The Plan agent verified the original plan's assumptions against the actual codebase and found several blockers. Key corrections:

1. **`FlipcashCore/Solana/` is the source of truth, not a re-export shim.** `AccountCluster`, `KeyPair`, `Mnemonic`, `PublicKey`, `Instruction` are *defined* there. There is no `@_exported import CodeServices` anywhere — the only `@_exported` is `import Logging` (swift-log) in `Logging/Exports.swift`. Phase "extract Solana shim" was rewritten as "extract Solana source-of-truth package."
2. **Persistence cannot be a leaf.** `Database+*.swift` files explicitly `import FlipcashCore` and operate on `Activity`, `Balance`, `PublicKey`, `Mnemonic`. The original "Persistence → Logging only" graph was a lie.
3. **A Kernel package is unavoidable.** `PublicKey`, `Mnemonic`, `KeyPair`, `AccountCluster`, `Quarks`, `Activity`, `Balance` are referenced by would-be Persistence + Networking + Core simultaneously. Added `FlipcashKernel` to hold them.
4. **`FlipcashCrypto` was a fiction.** Generic key types are co-mingled with Solana-domain types (`LaunchpadMint`, `GiftCardCluster`, `ProgramDerivedAccount`) inside `Solana/Keys/`. Two keychains exist (`FlipcashCore/Utilities/Keychain.swift` and `Flipcash/Keychain/Secure.swift`) — this is a code smell unrelated to the package split. Crypto package dropped; key value types go in Kernel; keychain consolidation tracked as a separate audit, not a phase.
5. **`CallOptions` is defined inline in `FlipcashCore/Clients/Payments API/Services/CodeService.swift`,** not in a transport file. Networking extraction has to split that file, not move it.
6. **Resources will trap moves.** `discrete_pricing_table.bin` / `discrete_cumulative_table.bin` are bundled into `FlipcashCore` and loaded via `Bundle.module` from `DiscreteBondingCurve.swift`. Whichever package owns `DiscreteBondingCurve` must own the resources too.
7. **Tests cross boundaries.** `DatabaseMintUpsertTests`, `StoredBalanceAppreciationTests`, `HistoryControllerTests`, `IntentTransferTests` already cross what will become package boundaries. Each extraction PR must redistribute or duplicate test imports.

---

## Why now

1. **API-boundary hygiene.** Today everything is `internal` to one of three giant packages, so `public` is meaningless and stale callers hide. Sub-packages turn `public` into a real API surface review.
2. **Swift 6 strict + `@MainActor` per package.** Concurrency defaults are set per package. Layered packages are concurrency-homogeneous (kernel/persistence/networking are nonisolated; UI is `@MainActor`); feature-mixed packages aren't, which is why we're not splitting by feature.
3. **Compile-time parallelism.** A flat dependency graph rebuilds in parallel. A fat core serializes everything.
4. **Dead-code audit.** Each extraction surfaces unused symbols ("only one caller" → delete) that are invisible inside a 200-file package.

---

## Non-goals

- **No feature packages.** `Withdraw/`, `Give/`, `Onramp/` etc. stay as folders inside the Flipcash app target — they are too coupled to `Session` and `AppRouter` to extract without making half the app `public`.
- **No changes to `FlipcashAPI` / `FlipcashCoreAPI`.** Generated proto packages — leave them alone.
- **No behavior changes.** Pure reorg + visibility tightening. Each phase must build and pass affected tests with no functional diff.
- **No mass modernization.** Swift 6 strict + `@MainActor` defaults are flipped *per package as it's extracted* — no big-bang migration of code that hasn't moved yet.
- **No keychain consolidation.** The two keychain implementations are an unrelated audit, tracked as follow-up work.

---

## Target package shape (revised)

| Package | Contents (today's location) | Concurrency default | Depends on |
|---|---|---|---|
| `FlipcashLogging` | `FlipcashCore/Sources/FlipcashCore/Logging/` (incl. `@_exported import Logging`) | nonisolated | swift-log |
| `FlipcashKernel` | Shared value types: `PublicKey`, `Mnemonic`, `KeyPair`, `AccountCluster`, `Quarks`/`Fiat`, `Activity`, `Balance`, common errors. Today scattered across `FlipcashCore/Solana/Keys/`, `FlipcashCore/Models/`. | nonisolated | `CodeCurves`, `BigDecimal` |
| `FlipcashSolana` | Solana-domain types: `LaunchpadMint`, `GiftCardCluster`, `ProgramDerivedAccount`, instructions, reserve state. Today in `FlipcashCore/Solana/` (excluding generic key types moved to Kernel). | nonisolated | `FlipcashKernel`, `CodeCurves` |
| `FlipcashPersistence` | `Flipcash/Core/Controllers/Database/` (incl. `Database+*.swift`, `Models/StoredBalance.swift`, `Models/StoredMintMetadata.swift`, `Schema.swift`). | nonisolated | `FlipcashKernel`, `FlipcashSolana`, `FlipcashLogging`, `dbart01/SQLite.swift` fork |
| `FlipcashNetworking` | gRPC `CallOptions` (split out of `CodeService.swift`), base client setup, interceptors, retry. | nonisolated | `FlipcashLogging`, `FlipcashAPI`, `FlipcashCoreAPI` |
| `FlipcashCore` (slim) | `Session`, controllers (`RatesController`, `HistoryController`, `NotificationController`, `PushController`), service definitions, business logic. | mixed (case-by-case `@MainActor`) | all leaves above |
| `FlipcashUI` | unchanged for now (Phase 7 flips concurrency default only) | `@MainActor` package default after Phase 7 | `FlipcashKernel`, `FlipcashCore`, `FlipcashLogging` |

**Heavy deps assignment:** `PhoneNumberKit` stays with `FlipcashCore` (used by phone-formatting utilities). `BigDecimal` belongs to `FlipcashKernel` (used by `Quarks`, `Fiat`). `CodeCurves` belongs to `FlipcashKernel` (used by `KeyPair`, `Mnemonic`, `AccountCluster`).

---

## Sequencing

Each phase ships as its own PR. Don't start phase N+1 until N is merged and the app boots clean. **All phases below are blocked by the legacy-deletion plan landing first.**

### Phase 1 — Filesystem mirror inside the existing 3 packages

Adopt Xcode 16 synchronized folders so `project.pbxproj` stops tracking individual files. This is a near-zero-risk reorg that sets up the layer extractions: file moves in subsequent phases stop touching the project file at all.

**Steps:**
1. Convert each target's group to a synchronized folder reference.
2. Move files where the on-disk path doesn't match the group (one folder at a time, verify build between).
3. Confirm `git status` shows only file moves + a much smaller `project.pbxproj` diff.

### Phase 2 — Extract `FlipcashLogging`

True leaf. Already a top-level folder, no internal deps beyond swift-log.

**Steps:**
1. New SwiftPM package `FlipcashLogging`.
2. `git mv FlipcashCore/Sources/FlipcashCore/Logging/* FlipcashLogging/Sources/FlipcashLogging/`.
3. Preserve the `@_exported import Logging` — callers continue to write `import FlipcashLogging` and get `swift-log` for free.
4. Make types `public` that are used outside the new package; keep everything else `internal`.
5. Add `import FlipcashLogging` everywhere a logger is created.
6. Set Swift 6 strict + nonisolated default in this package's `Package.swift`.
7. Audit + delete unused symbols surfaced by the `public`-vs-`internal` review.

**Acceptance:** `./Scripts/build.sh` clean, `FlipcashLoggingTests` (new test target) green, affected suites in `FlipcashCoreTests`/`FlipcashTests` green.

### Phase 3 — Extract `FlipcashKernel` (multi-PR)

Foundational shared types. This is the highest-blast-radius phase — `PublicKey`, `Mnemonic`, `Quarks`, etc. are referenced everywhere, and the diff will touch hundreds of files for `import` updates alone. Landing it as a single PR is unreviewable, so it ships in three sub-phases. Each sub-phase is its own PR; the package itself is created in 3a and grows in 3b and 3c.

**Phase 3a — Currency value types.** Smallest, additive.
- From `FlipcashCore/Models/`: `Quarks.swift`, `Fiat.swift`, `ExchangedFiat.swift`, `Currency.swift`, common error types.
- Heavy dep `BigDecimal` moves into Kernel.
- Creates the `FlipcashKernel` package and its test target.

**Phase 3b — Crypto key types.** Medium.
- From `FlipcashCore/Solana/Keys/`: `PublicKey.swift`, `Mnemonic.swift`, `KeyPair.swift`, `Derive.swift` (key-derivation helpers only — Solana-program-derived-address stays in `FlipcashCore/Solana/` for now, moves in Phase 4).
- Heavy dep `CodeCurves` moves into Kernel.

**Phase 3c — Account + business value types.** Largest, most callers.
- From `FlipcashCore/Solana/Keys/`: `AccountCluster.swift`.
- From `FlipcashCore/Models/`: `Activity.swift`, `Balance.swift`.
- **Risk:** `Activity` and `Balance` may have business-logic methods (not just data). Read each one before moving — anything that does I/O or calls a controller stays in slim Core as an extension; only the value type goes to Kernel.

### Phase 4 — Extract `FlipcashSolana`

Solana-domain types that are not generic primitives.

**Contents to move:**
- Remainder of `FlipcashCore/Solana/` after Kernel takes the generic key types: `LaunchpadMint.swift`, `GiftCardCluster.swift`, `ProgramDerivedAccount.swift`, instruction builders, reserve-state types.
- This is also where `IntentTransfer`, `IntentWithdrawal`, etc. *might* belong — read them before deciding. If they're transport-shaped, they go here; if they're orchestration-shaped (compose AccountCluster + RPC calls), stay in slim Core.

### Phase 5 — Extract `FlipcashPersistence`

SQLite layer. Owns the largest physical move — the database lives in the **app target** today.

**Contents to move:**
- `Flipcash/Core/Controllers/Database/Database.swift`
- `Flipcash/Core/Controllers/Database/Schema.swift`
- All `Database+*.swift` extensions (`Database+Balance.swift`, `Database+Activity.swift`, `Database+Mints.swift`, etc.)
- `Flipcash/Core/Controllers/Database/Models/StoredBalance.swift`, `StoredMintMetadata.swift`

**Steps:**
1. New package depends on `FlipcashKernel` + `FlipcashSolana` + `FlipcashLogging` + `dbart01/SQLite.swift` fork.
2. Move files, update imports.
3. Walk every `Database+*.swift` extension and confirm the types it operates on (`Activity`, `Balance`, `PublicKey`, `Mnemonic`) all resolve via Kernel/Solana, not via slim Core. If any extension references a slim-Core-only type, that's a sign the type was misclassified in Phase 3 — go back and fix Kernel.
4. Move affected tests to a new `FlipcashPersistenceTests` target: `DatabaseMintUpsertTests`, `StoredBalanceAppreciationTests`, anything currently in `FlipcashTests` that exercises database code.

**Note for Phase 4 sequencing:** `IntentTransferTests` exercises both `AccountCluster.mock` (Kernel after Phase 3) and `IntentTransfer` (Solana or slim-Core after Phase 4). When IntentTransfer's location is decided, the test target moves with it.

### Phase 6 — Extract `FlipcashNetworking`

Transport layer.

**Contents to move:**
- gRPC `CallOptions` extension — currently inline at `FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Services/CodeService.swift:17-21`. Split this out of `CodeService.swift` into `FlipcashNetworking/CallOptions.swift`. The service file stays in slim Core.
- Base gRPC client setup, interceptors, retry, keepalive config.

Service definitions (`PaymentsService`, `OcpService`, etc.) stay in slim `FlipcashCore` for now — they're business-logic-shaped, not transport-shaped.

### Phase 7 — Slim `FlipcashCore` audit pass

After Phases 2–6, `FlipcashCore` should consist of: `Session`, controllers, service definitions, orchestration logic, anything that's still `@MainActor`-mixed.

**Steps:**
1. Delete files now empty of relevant content.
2. Update CLAUDE.md: revise the "Hard Rules / Module Boundaries" section. The "Flipcash must NEVER import CodeServices" rule becomes obsolete (CodeServices was deleted in the legacy-deletion plan). Replace with the new layered-package rule and dep graph.
3. Confirm slim-Core's `Package.swift` deps match the new graph.

### Phase 8 — Flip `FlipcashUI` to `@MainActor` package default

Should be a one-liner in `Package.swift`. **Red-team noted:** 10+ files in `FlipcashUI/Views/` `import FlipcashCore` directly (`AccessKey`, `Flag`, `AmountText`, `Chart` and others). Flipping the default will surface every nonisolated helper currently leaked through Core that's being called from UI code. Expect a cleanup tail of `nonisolated` annotations or type relocations.

---

## Per-extraction checklist (Phases 2–6)

Every layer extraction follows the same loop:

1. Add new package + `Package.swift` with Swift 6 strict + correct concurrency default.
2. `git mv` source files (keeps blame).
3. **Move resources with their consumers.** If a moved file calls `Bundle.module`, the resource bundle entry in `Package.swift` follows. `discrete_pricing_table.bin` and `discrete_cumulative_table.bin` move with `DiscreteBondingCurve.swift`.
4. Add the new package as a dependency wherever it's needed.
5. Change `internal` → `public` only for symbols actually used outside the new package. **This is the audit step** — flag everything that no longer needs to be `public`, and anything no longer used at all.
6. Update imports.
7. Move affected tests to a new sibling test target (e.g. `FlipcashLoggingTests`); leave `FlipcashTests` for app-level integration tests only.
8. Build + run affected tests.
9. Commit. PR.

Plans for each phase get their own `.claude/plans/YYYY-MM-DD-extract-<package>.md` file when the work starts — this top-level plan is the index, not the per-phase detail.

---

## Risks & unknowns

- **Activity / Balance straddle (Phase 3).** If these types contain controller-coupled methods, they can't fully move to Kernel. Mitigation: split into `Activity` (value type, Kernel) + `Activity+*` extensions (slim Core). Confirm by reading both files end-to-end before starting Phase 3.
- **`@MainActor` flip surfaces nonisolated leaks (Phase 8).** UI files import slim Core directly. Expect `nonisolated` annotations or `MainActor.assumeIsolated` wrappers in the cleanup tail.
- **Test target sprawl.** Each new package wants its own test target. SwiftPM test targets are cheap; Xcode scheme bookkeeping isn't. Confirm `./Scripts/test.sh` still routes correctly after each phase.
- **`Package.resolved` churn.** Adding 4–5 new packages means workspace `Package.resolved` rewrites every phase — committed per CLAUDE.md policy, expect noisy diffs.
- **Two keychains (out of scope).** `FlipcashCore/Utilities/Keychain.swift` and `Flipcash/Keychain/Secure.swift` both exist. Tracked as a separate audit, not a phase.

---

## Decisions (resolved)

- **Naming:** keep the `Flipcash*` prefix for all new packages.
- **Phase 3 packaging:** ship as three PRs (3a, 3b, 3c).
- **Phase 7 checkpoint:** keep it. After slim-Core audit, decide whether to peel further (e.g. `Onramp`, `Withdraw` *controllers* into their own packages) before flipping UI in Phase 8.

---

## Status

| Phase | Status | Notes |
|---|---|---|
| Prereq — Legacy deletion | See `2026-05-02-legacy-app-deletion.md` | Blocking |
| 1 — Filesystem mirror | Not started | |
| 2 — `FlipcashLogging` | Not started | True leaf |
| 3a — `FlipcashKernel`: currency value types | Not started | Creates package |
| 3b — `FlipcashKernel`: crypto key types | Not started | |
| 3c — `FlipcashKernel`: account + business types | Not started | Largest sub-phase |
| 4 — `FlipcashSolana` | Not started | |
| 5 — `FlipcashPersistence` | Not started | Largest physical move |
| 6 — `FlipcashNetworking` | Not started | Splits `CodeService.swift` |
| 7 — Slim-Core audit | Not started | Checkpoint: decide further splits |
| 8 — `FlipcashUI` `@MainActor` default | Not started | Cleanup tail likely |
