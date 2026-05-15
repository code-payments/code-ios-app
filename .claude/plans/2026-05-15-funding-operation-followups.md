# FundingOperation refactor — deferred follow-ups

**Date:** 2026-05-15
**Branch:** `refactor/funding-operation-protocol` (rebased onto `main`; ships the amount-first buy flow + the FundingOperation protocol family in one PR)
**Status:** Main refactor landed; follow-ups below open for a fresh session.

Companion to `.claude/plans/2026-05-14-funding-strategy-protocol.md` — that spec defined the architecture; this doc tracks what's left and how to pick each piece up cold.

---

## What landed

| SHA | Milestone |
|---|---|
| fb18217e | Dependency protocols (`TransactionSigning`, `OnrampOrdering`, `ContactVerifying`, `OnrampAuthorizing`, 8 Session-side protocols) |
| a65bb173 | `FundingOperation` protocol + `StartedSwap`, `FundingOperationState`, `UserPrompt`, `ExternalPrompt`, `FundingRequirement`, `FundingOperationError`; `SwapType` extended with `launchWith{Reserves,Phantom,Coinbase}` and marked `nonisolated` |
| 61a756ef | `VerificationOperation` (standalone phone+email verifier) + `waitUntil` test helper + tests |
| e735c7a6 | **Reserves end-to-end** — `ReservesFundingOperation` + `BuyAmountViewModel.performBuy` + wizard `launchAndBuyWithReserves` |
| 2918cd77 | `PhantomFundingOperation` (operation only, no call-site migration) |
| aee0be3a | **Phantom end-to-end** — replaces `PhantomCoordinator`, `PhantomCoordinatorTests`, `WalletProcessingStateTests`, `ExternalSwapProcessing` |
| 28d3a682 | **Coinbase end-to-end** — `CoinbaseFundingOperation` + session-scoped `CoinbaseService` |
| 64dc9683 | **Phantom flow reshape** — single `PhantomFlowScreen` replaces the two pushed prompt screens. `PhantomFundingOperation.run()` now retries internally on wallet-side cancel; cancel reason surfaces via `session.dialogItem`. Success path uses `AppRouter.replaceTopmostAny` so back-swipe can't reveal a terminal-state flow. Deletes `FundingFlowHost`, `fundingPrompt(for:)`, `FundingPromptDestination`. |
| 6a8ba6ef | Keep Phantom callback URLs (`/wallet/walletConnected`, `/wallet/transactionSigned`) as `.unknown` after main's home-screen quick-action route added `case "wallet"`. |

All three funding paths (Reserves / Phantom / Coinbase) run end-to-end on the new operation contract. Targeted tests pass.

---

## Architectural map (read first)

```
SessionContainer
├── OnrampCoordinator               # STILL ALIVE — verification UI only
├── CoinbaseService                 # session-scoped: WebView state + Apple Pay events stream + Coinbase actor
└── WalletConnection                # session-scoped: Phantom handshake + sign request + deeplink events stream

PaymentOperation (the picker payload — buy or launch)
└── LaunchPayload.attestations: LaunchAttestations?  # required for op-driven launch
    .verifiedState: VerifiedState?                   # required for reserves launch only

FundingOperation (protocol)
├── ReservesFundingOperation     # no requirements; buy / launch via session.buy / launchCurrency+buyNewCurrency
├── PhantomFundingOperation      # no requirements; two retry loops — education → handshake (loops on cancel) → confirm → sign (loops on cancel) → server-notify → chain submit
│                                # `launchedMint` observable for nameExists-retry hooks; `lastErrorMessage` drives session.dialogItem
└── CoinbaseFundingOperation     # requirements [.verifiedContact]; createOrder → Apple Pay overlay → server-notify

PhantomFlowScreen — single state-switching host. Renders the education / confirm panel based on `operation.state`; `.awaitingExternal(.phantomConnect|.phantomSign)` keep their respective panel in a "busy" CTA state. A sticky `@State hasShownConfirm` flag keeps the Confirm panel up through `.working` (post-sign submit) so the wallet→chain hand-off is visually continuous. `.onChange(of: operation.lastErrorMessage)` writes `session.dialogItem = .walletCancelled` so the alert renders above the sheet.

Caller pattern (BuyAmountViewModel / wizard):
1. viewModel holds `var fundingOperation: (any FundingOperation)?`
2. User picks a method → viewmodel constructs the right op + sets fundingOperation
3. For Phantom: viewmodel pushes `.phantomFlow(operation)` directly (no host modifier — the destination renders against `operation.state` until terminal)
4. Task awaits op.start(payment); on success use `router.replaceTopmostAny(BuyFlowPath.processing(...))` (buy) or `router.popTopmost() + phantomLaunchContext = …` (wizard cover); on non-cancel throw, dialog
```

**Hashable on operations:** `PhantomFundingOperation` has a `nonisolated extension … : Hashable` (identity-based) so it can ride inside the `nonisolated AppRouter.Destination.phantomFlow(_:)` case. Other ops don't need Hashable (they don't appear in destinations).

**Module isolation:** the app target uses `-default-isolation=MainActor` with `NonisolatedNonsendingByDefault` enabled. Pure data types are marked `nonisolated`; operation classes are implicitly main-actor. Async protocol methods preserve caller isolation. Protocols that need to be reachable across this boundary live in the app target (not FlipcashCore), e.g. `FlipClient+Protocols.swift`.

---

## Deferred items

### 1. `CoinbaseFundingOperationTests`

**Why it matters:** Reserves, Phantom, Verification, and FundingFlowHost have tests. Coinbase doesn't. The operation pattern is verified, but Coinbase-specific paths (Apple Pay event handling, server-notify ordering relative to events) aren't.

**Why deferred:** `OnrampOrderResponse` is awkward to construct in tests — nested `Order` struct with many required fields, no public init, only Decodable. `ApplePayEvent` has the same issue (memberwise init is internal). Both are reachable via `@testable import Flipcash`, so it's a few lines of helper code, not blocked.

**How to pick up:**
1. Write a `MockOnrampOrdering` in `FlipcashTests/TestSupport/` — a `@unchecked Sendable` class with a `createOrderHandler` closure and a default fixture for the response.
2. The response fixture needs `OnrampOrderResponse(order:, paymentLink:)`. Use the internal memberwise init via `@testable`.
3. `ApplePayEvent` likewise — construct via memberwise init.
4. Test scenarios to cover (parallel to `PhantomFundingOperationTests`):
   - `.buy` happy path → `createOrder` → yield `pollingSuccess` event → `StartedSwap(swapType: .buyWithCoinbase)`
   - `.launch` happy path → preflight `launchCurrency` → `createOrder` → `pollingSuccess` → `StartedSwap(swapType: .launchWithCoinbase, launchedMint: non-nil)`
   - Missing attestations on `.launch` → `serverRejected`
   - Profile not verified → `requirementUnsatisfied(.verifiedContact)`
   - `pollingError` event → `serverRejected(message)`
   - `cancelled` event → `CancellationError`
   - `commitError` event → `serverRejected`
   - `coinbase.createOrder` throws `OnrampErrorResponse` → mapped to `serverRejected`

**Files:**
- New: `FlipcashTests/CoinbaseFundingOperationTests.swift`
- New: `FlipcashTests/TestSupport/MockOnrampOrdering.swift`
- Maybe: `FlipcashTests/TestSupport/ApplePayEvent+Fixtures.swift`
- Use existing: `FlipcashTests/TestSupport/MockSession.swift`, `WaitForState.swift`

---

### 2. Strip dead Coinbase code from `OnrampCoordinator`

**Why it matters:** ~400 lines of dead code in `OnrampCoordinator.swift`. No call sites reach these methods after commit 28d3a682, but the file still carries them. Cleanup makes the file's intent (verification only) obvious.

**Dead methods/properties to remove from `Flipcash/Core/Controllers/Onramp/OnrampCoordinator.swift`:**
- `coinbaseOrder` property
- `completion`, `buyCompletionBinding`, `launchCompletionBinding`
- `isProcessingPayment` — **but check**: `BuyAmountScreen.isDismissBlocked` still reads it. After cleanup, replace that check with `coinbaseService.coinbaseOrder != nil` only.
- `coinbase: Coinbase!` property + the `Coinbase(configuration:)` construction in `init` + `coinbaseApiKey` reading from InfoPlist + `fetchCoinbaseJWT(method:path:)`
- `applePayIdleTimer: ApplePayIdleTimer` + the entire `ApplePayIdleTimer` class definition (probably its own file)
- `pendingOperation`, `pendingAmount`, `pendingSwapId` (the legacy pending state — `start(_:amount:)` populated them)
- `start(_:amount:)` — legacy entry point; replaced by `startVerification(onComplete:)`
- `navigateToVerificationOrPurchase(for:amount:)` — only called by legacy `start`
- `createOrder(amount:operation:)` — legacy
- `initiateCoinbaseOnrampSwap(for:amount:orderId:)` — legacy
- `makeOnrampCompletion(for:swapId:amount:)` — legacy
- `receiveApplePayEvent(_:)` — legacy
- `handleCoinbaseOnrampSuccess()` — legacy
- `showBuyFailedDialog()` — only called by `handleCoinbaseOnrampSuccess` / `createOrder` failure
- `OnrampOperation` enum — legacy payload; was the input to `start(_:amount:)`
- `enum Origin: Int` private to OnrampCoordinator — check whether still used by remaining verification methods
- `clearPendingState()` — only used by legacy paths; check if anything else calls it

**Keep:**
- All `verificationPath` / `enteredPhone` / `enteredCode` / `enteredEmail` / `region` / `phoneFormatter` / button states
- `sendPhoneNumberCodeAction`, `resendCodeAction`, `confirmPhoneNumberCodeAction`, `sendEmailCodeAction`, `resendEmailCodeAction`, `applyDeeplinkVerification`
- `navigateToInitialVerification`, `navigateToAmount(from:)`
- `startVerification(onComplete:)` and `onVerificationComplete` callback
- All dialog factory methods used by verification
- Bindings (`adjustingPhoneNumberBinding`, `adjustingCodeBinding`)
- `pasteCodeFromClipboardIfPossible`
- `regionFlagStyle`, `countryCode`, `phone`, `canSendVerificationCode`, etc.
- `setRegion(_:)`

**After cleanup:** `OnrampCoordinator` should be ~half its current size, file name no longer accurate. Consider renaming the file + class to `VerificationCoordinator` in the same commit. Update all `@Environment(OnrampCoordinator.self)` references — there are ~5 verification screens plus `BuyAmountScreen` (gates `isDismissBlocked`) plus the wizard (the `startVerification` caller).

`OnrampCoordinatorTests` likely has assertions on legacy behavior — review and prune.

---

### 3. Fully delete `OnrampCoordinator` (extract `VerificationViewModel`)

**Why it matters:** Item #2 trims it to verification, but the plan called for full deletion. To get there, the 5 verification screens need to bind to a `VerificationViewModel` instead.

**Why deferred:** 5 screen refactors + view-state migration is a big chunk for one PR. The new operation contract is fine without it.

**How to pick up:**
1. Create `Flipcash/Core/Screens/Onramp/VerificationViewModel.swift` — `@Observable @MainActor final class` holding everything in item #2's "Keep" list (verification view state + actions). Owns a `VerificationOperation` instance internally; the verification actions resume the op's continuations.
2. Update each verification screen: replace `@Environment(OnrampCoordinator.self) private var onrampCoordinator` with a `let viewModel: VerificationViewModel` parameter (passed by caller).
   - `Flipcash/Core/Screens/Onramp/VerifyInfoScreen.swift`
   - `Flipcash/Core/Screens/Onramp/EnterPhoneScreen.swift`
   - `Flipcash/Core/Screens/Onramp/ConfirmPhoneScreen.swift`
   - `Flipcash/Core/Screens/Onramp/EnterEmailScreen.swift`
   - `Flipcash/Core/Screens/Onramp/ConfirmEmailScreen.swift`
3. Caller pattern (`BuyAmountViewModel.startCoinbaseFunding` and wizard's `startCoinbaseLaunchFunding`):
   - If `session.profile?.isFullyVerified == true`, skip verification — go straight to `CoinbaseFundingOperation`.
   - Else, construct `VerificationViewModel`, store on the caller's viewmodel/wizard `@State`, present verification sheet, `await verificationViewModel.run()` (returns when both phone+email are verified), then continue with `CoinbaseFundingOperation`.
4. `OnrampHostModifier.applyDeeplinkVerification(_:)` currently routes the email-verification deeplink to `OnrampCoordinator`. Route it to the active `VerificationViewModel` (or to a session-scoped `VerificationDeeplinkInbox` the viewmodel reads from). The deeplink can arrive when no flow is active — the inbox should buffer it.
5. Delete `OnrampCoordinator.swift` and `OnrampCoordinatorTests.swift`.
6. `BuyAmountScreen` and the wizard drop `@Environment(OnrampCoordinator.self)`.
7. `SessionAuthenticator` drops `onrampCoordinator: OnrampCoordinator` construction + env injection.

**Estimated size:** ~600 lines net change (mostly mechanical screen rewrites).

---

### 4. Phantom `nameExists` retry on launch

**Why it matters:** Reserves preserves nameExists retry (see `CurrencyCreationWizardScreen.launchAndBuyWithReserves`'s `nameExists` catch → reuses `createdMint`). Phantom doesn't. If a Phantom launch attempt succeeds at `launchCurrency` but fails afterwards (e.g., user dismisses Phantom mid-sign), the next attempt re-runs `launchCurrency` server-side and hits `nameExists` with no escape.

**Why deferred:** Edge case (the chain has to fail after `launchCurrency` succeeded but before sign completes).

**How to pick up:**
1. Add `preLaunchedMint: PublicKey?` to `PaymentOperation.LaunchPayload`. Defaults to nil.
2. In `PhantomFundingOperation.preflightLaunchIfNeeded(_:)`, if `payload.preLaunchedMint != nil`, skip the `session.launchCurrency` call and set `launchedMint = payload.preLaunchedMint`.
3. In the wizard's `startPhantomLaunchFunding` (and `startCoinbaseLaunchFunding` for symmetry), when constructing the payload, check `createdMint?.name == state.currencyName` and pass that mint as `preLaunchedMint`.
4. Test: write a test in `PhantomFundingOperationTests` that runs `.launch` twice — first attempt mocks `launchCurrency` to succeed but `sendUsdcToUsdfSignRequest` to throw; verify `op.launchedMint` is captured. Second attempt passes `preLaunchedMint = capturedMint`; verify `launchCurrency` is NOT called.

Apply the same hint to `ReservesFundingOperation` to remove the direct `session.buyNewCurrency` retry shortcut at the call site (currently in `wizard.launchAndBuyWithReserves`'s nameExists catch). Optional — current direct call works.

---

### 5. Coverage-preservation table

**Why it matters:** The plan's pre-implementation gate #4 + commit #8 called for an explicit mapping from each deleted-coordinator test scenario to a new-shape test. Used as the "zero coverage drop" artifact.

**Why deferred:** Time. The new operation tests cover the same flow shapes; the mapping is mechanical.

**How to pick up:** Build the table in the PR description (or in this doc). The deleted suites:

- `FlipcashTests/Phantom/PhantomCoordinatorTests.swift` (deleted in aee0be3a) — 6 scenarios about state-machine transitions
- `FlipcashTests/OnrampCoordinatorTests.swift` (still present, mostly verification scenarios) — keep for verification tests, prune any Coinbase legacy assertions

Each scenario maps to either:
- A test in `PhantomFundingOperationTests`
- A test in `CoinbaseFundingOperationTests` (item #1 above)
- A test in `VerificationOperationTests`
- Or a row marked "intentionally dropped — behavior change documented" with a one-line rationale.

Use `git show aee0be3a:FlipcashTests/Phantom/PhantomCoordinatorTests.swift` to read the deleted file.

---

## Files of interest

**Operations:**
- `Flipcash/Core/Screens/Main/Operations/FundingOperation.swift` (protocol + state types — `FundingOperationState`, `UserPrompt`, `ExternalPrompt` with `.phantomConnect` / `.phantomSign` / `.applePay`, `FundingRequirement`, `FundingOperationError`)
- `Flipcash/Core/Screens/Main/Operations/ReservesFundingOperation.swift`
- `Flipcash/Core/Screens/Main/Operations/PhantomFundingOperation.swift` (two-loop retry, `lastErrorMessage`, `cancelPendingConfirm` helper)
- `Flipcash/Core/Screens/Main/Operations/CoinbaseFundingOperation.swift`
- `Flipcash/Core/Screens/Main/Operations/VerificationOperation.swift`

**Phantom flow UI:**
- `Flipcash/Core/Screens/Main/Buy/PhantomFlowScreen.swift` (single host + `PhantomFlowPanel<Hero, ButtonLabel>` scaffold)

**Service:**
- `Flipcash/Core/Controllers/Onramp/CoinbaseService.swift`

**Dependency protocols (single-concern, `-ing` capability suffix):**
- `Flipcash/Core/Controllers/Deep Links/Wallet/TransactionSigning.swift`
- `Flipcash/Core/Controllers/OnrampOrdering.swift`
- `Flipcash/Core/Controllers/FlipClient+Protocols.swift` (ContactVerifying + OnrampAuthorizing)
- `Flipcash/Core/Session/SessionProtocols.swift` (8 Session protocols)

**Call sites:**
- `Flipcash/Core/Screens/Main/Buy/BuyAmountViewModel.swift` (`startPhantomFunding` pushes `.phantomFlow` then `replaceTopmostAny(.processing)` on success; `startCoinbaseFunding`)
- `Flipcash/Core/Screens/Main/Buy/PurchaseMethodSheet.swift` (Apple Pay / Phantom / Other Wallet rows)
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationWizardScreen.swift` (`startPhantomLaunchFunding`, `startCoinbaseLaunchFunding`, `launchAndBuyWithReserves`)

**Router helpers:**
- `AppRouter.popTopmost()` and `AppRouter.replaceTopmostAny(_:)` — mirror the `push` / `pushAny` split.

**Tests:**
- `FlipcashTests/ReservesFundingOperationTests.swift`
- `FlipcashTests/PhantomFundingOperationTests.swift` (happy path + connect-cancel retry + sign-cancel retry + external-cancel breaks loop)
- `FlipcashTests/VerificationOperationTests.swift`
- `FlipcashTests/TestSupport/MockSession.swift` (cached `AccountCluster.mock` / `KeyPair.mock` — avoid building `Session.mock` per test)
- `FlipcashTests/TestSupport/MockTransactionSigning.swift` (uses `AsyncStream.makeStream(of:)`)
- `FlipcashTests/TestSupport/MockSolanaRPC.swift`
- `FlipcashTests/TestSupport/WaitForState.swift` (timeout messages reflect the observed object state)

---

## Test patterns that work (so future tests follow them)

**Suite-level `@MainActor`** — declared once, not per-test:
```swift
@Suite("MyOperation") @MainActor
struct MyOperationTests { ... }
```

**Continuation-driven flow tests** — spawn `start()` as `async let`, drive submissions, then await:
```swift
async let result = op.start(payment)
try await waitUntil(op) { $0.state == .awaitingUserAction(.education(...)) }
op.confirm()
try await waitUntil(op) { $0.state == .awaitingUserAction(.confirm(...)) }
op.confirm()
let swap = try await result
```

**Cancel-throws-CancellationError** — every test that calls `start()` must either await the result or call `cancel()` and assert `CancellationError`. Otherwise pending tasks leak.

**`#expect(throws:)` for typed errors** — Swift Testing's typed throws:
```swift
await #expect(throws: FundingOperationError.self) {
    try await op.start(payload)
}
```

---

## Quick start for next session

1. Read this file.
2. `git log --oneline origin/main..HEAD` to see what landed (the branch lives on top of `main`).
3. Pick a deferred item.
4. Each item is self-contained — pick whichever has the least context-loading needed.
5. Commit naming: keep `refactor:` prefix; squash-on-merge so per-commit messages are functional, not polished.
