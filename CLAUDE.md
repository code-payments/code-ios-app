# Claude Guidelines for Flipcash iOS

This file provides instructions for Claude when working on the Flipcash iOS codebase.

---

## Maintaining This Document

**Claude should proactively update this file** when discovering critical information that would prevent mistakes or save significant time in future sessions. This includes:

- New hard rules or constraints discovered through errors
- Critical patterns that aren't obvious from the code
- Module boundaries or dependencies that caused issues
- Non-obvious project conventions

**Keep this document lean.** Only add information that is:
1. Not discoverable by reading the code directly
2. Would cause errors or significant rework if unknown
3. Applies broadly across the project (not one-off edge cases)

When adding new information, place it in the appropriate existing section. Remove outdated information when it no longer applies.

---

## Plans & Analysis Records

**Record analyses and implementation plans in `.claude/plans/`** when:

- Performing deep-dive analysis of new features or RPC changes
- Planning multi-step implementations
- Documenting architectural decisions
- Investigating complex systems that span multiple files

**File naming:** `YYYY-MM-DD-<topic>.md` (e.g., `2025-11-27-swap-rpc-analysis.md`)

**Purpose:** These records allow future sessions to reference prior analysis without re-exploring the codebase. Keep them detailed but focused on actionable information.

---

## Reflections

**Review [`.claude/reflections/index.md`](.claude/reflections/index.md) before making changes.** This log documents past situations where fixes went off track — over-engineering, breaking existing patterns, or introducing regressions. Reading it helps avoid repeating the same mistakes.

---

## Behavior & Approach

### Working Style

- **Understand the context.** Take your time to understand how the changes _should_ fit into the complete project. Perhaps a refactor is required. Perhaps the current structure is not ideal. Take your time to identify this.
- **Double-check your work.** Verify changes compile and don't break existing functionality.
- **Ask clarifying questions.** When requirements are ambiguous or something is unclear or can have multiple meanings, don't assume. Ask clarifying questions where needed but try to keep these as concise and as minimal as possible.

### Before Making Changes

1. Read the relevant files first - never propose changes to code you haven't read
2. Understand the existing patterns and conventions in the current file but also any related or dependant files
3. Check module boundaries (see Hard Rules below)
4. Consider impact on other parts of the codebase

### Communication

- Be direct and concise
- When uncertain, say so rather than guessing
- Provide file paths with line numbers when referencing code (e.g., `Session.swift:326`)

---

## Hard Rules (Non-Negotiable)

### Testing Framework

**Use Swift Testing, NOT XCTest:**

```swift
// ❌ WRONG
import XCTest
class MyTests: XCTestCase { ... }

// ✅ CORRECT
import Testing
@Suite struct MyTests { ... }
```

### Exhaustive Switch Statements

**Always prefer `switch` over `if case` for enums:**

```swift
// ❌ BAD: Silent failure if enum changes
guard case .sufficient(let amount) = result else {
    showError()
    return
}

// ✅ GOOD: Compiler error if enum changes
switch result {
case .sufficient(let amount):
    handleSuccess(amount)
case .insufficient(let shortfall):
    handleError(shortfall)
}
```

### Modernize Incrementally

**When writing new code or touching isolated screens, prefer modern Swift/SwiftUI APIs.** This is a gradual migration — don't refactor working code just to modernize it, but do use modern patterns in net-new or self-contained work.

| Legacy | Modern | Notes |
|--------|--------|-------|
| `ObservableObject` / `@Published` | `@Observable` | Use `@State` in views instead of `@StateObject` |
| `@EnvironmentObject` | `@Environment` | For new dependencies; existing `@EnvironmentObject` stays until the injected type is migrated |
| `@AppStorage` wrapping `UserDefaults` manually | `@AppStorage` directly | For simple per-screen preferences |
| `onChange(of:perform:)` (deprecated) | `onChange(of:initial:_:)` | Use `initial: true` when the handler should also fire on appear |

Existing `ObservableObject` classes (`Client`, `FlipClient`) stay as-is until their dependents are migrated. A single class must use one system — either `ObservableObject` with `@Published`, or `@Observable`. Mixing causes silent observation failures.

### Generated Files

**Never modify files under `Generated/` directly** — they're regenerated from upstream protos by the scripts in [Regenerating Protos](#regenerating-protos), and any local edits will be overwritten. Update the service files that wrap the generated code instead.

### Database Schema Changes

**Bump `SQLiteVersion` in Info.plist on every schema change.** The app does not run migrations — when the version number increases, the database is deleted and rebuilt from server data on next login (`SessionAuthenticator.initializeDatabase`). This means:

- Adding/removing tables or columns → bump version
- Changing which table a query reads from → bump version if the old schema can't satisfy the new query
- No migration code needed, but all data must be recoverable from server

### Logging: Variables Go in Metadata

**All variable data must go in structured `metadata`. The message string is a constant, free-form description.** Two reasons, in order of importance:

1. **Privacy.** The redactors (`PatternRedactor`, `SensitiveKeyRedactor` in `FlipcashCore/Sources/FlipcashCore/Logging/Middleware/`) only scan `entry.metadata`. Anything interpolated into the message is written verbatim to the file export, the Bugsnag ring buffer attachment, and OSLog. Putting *every* variable in metadata means values that look innocent today get the redactor safety net automatically — instead of relying on developers to spot which ones are sensitive.
2. **Queryability.** Metadata is structured key=value, so you can `grep owner=` or filter by key in a structured log viewer. Interpolated values get baked into a string and lose their key.

```swift
// ❌ BAD: leaks the public key in plaintext to every log sink
logger.info("New encryption box, public key: \(box.publicKey.base58)")

// ❌ BAD: even non-sensitive variables don't belong in the message
logger.info("Requested swap of \(amount) for \(token.symbol)", metadata: [
    "swapId": "\(swapId.base58)",
])

// ✅ GOOD: message is a constant, every variable is in metadata
logger.info("New encryption box", metadata: ["publicKey": "\(box.publicKey.base58)"])
logger.info("Requested swap", metadata: [
    "amount": "\(amount)",
    "token": "\(token.symbol)",
    "swapId": "\(swapId.base58)",
])
```

**Never log proto blobs whole.** A naked `\(response.tokenAccountInfos)` or `\(notification)` recursively serializes every field, including the base58 ones. Extract the specific diagnostic values you actually need into metadata instead — usually a count, a type, or an error, not the whole record.

### Error Reporting: Always Call `captureError` Unconditionally

**Call `ErrorReporting.captureError(error, reason: ...)` directly — never gate it on `reportingLevel` at the call site.** The reporter handles that internally in `ErrorReporting.capture(_:)`, mapping the level onto Bugsnag severity (or dropping the event):

```swift
// Inside ErrorReporting (Flipcash/Utilities/ErrorReporting.swift)
let level = (error as? ServerError)?.reportingLevel ?? .error  // non-ServerError → real bug
switch level {
case .suppressed: return            // dropped — never sent
case .info:       severity = .info  // visible, low-priority
case .error:      severity = .error
}
```

Duplicating the check at the call site is dead code and drifts from every other site in the codebase.

```swift
// ❌ BAD: rechecks what ErrorReporting already filters
if (error as? ServerError)?.reportingLevel != .suppressed {
    ErrorReporting.captureError(error, reason: "...")
}

// ✅ GOOD: just call it
ErrorReporting.captureError(error, reason: "...")
```

To change how a specific error type surfaces, conform it to `ServerError` (in `FlipcashCore/Sources/FlipcashCore/Models/ServerError.swift`) and return the right `ErrorReportingLevel` per case — `.suppressed` for network weather / success sentinels, `.info` for expected business outcomes (denied, not-found, rate-limited), `.error` for client/proto defects (`.unknown`, parse failures). There is deliberately no protocol default — the compiler forces every new conformer to classify its cases explicitly. That's the single source of truth — call sites stay uniform.

### Form Input Validation: Use the `Validator` Family

**Validate free-form input through `Validator` (in `FlipcashCore/Sources/FlipcashCore/Validation/`), not inline regex/trim/length checks.** Each input type gets a concrete validator (`EmailValidator`, `PhoneValidator`, `CurrencyNameValidator`, `LengthValidator`) that owns the rule, returns the canonical form, and is unit-testable in isolation.

```swift
// ❌ BAD: inline rule in the viewmodel — drifts from the server contract, untestable
var canSendEmail: Bool {
    let trimmed = enteredEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.wholeMatch(of: emailRegex) != nil
}

// ✅ GOOD: route through the validator
@ObservationIgnored private let emailValidator = EmailValidator()

var validatedEmail: String? { emailValidator.validate(enteredEmail) }
var canSendEmail: Bool { validatedEmail != nil }
```

**Submit the validator's `Output`, not the raw input.** That's how trim/regex divergence is structurally impossible — there's one path from input to wire and the canonical form lives on it.

**Why:** client validation must mirror the server contract (typically a PGV regex from a `.proto`). A single `Validator` per input type is the canonical source; inline rules in screens or viewmodels drift the moment the proto changes.

### Package.resolved Policy

**Always commit the workspace Package.resolved:**

- ✅ `Code.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` - MUST be committed
- ❌ Individual package `Package.resolved` files - ignored by git

This ensures deterministic builds across all developers and CI systems while minimizing merge conflicts. The workspace Package.resolved is the single source of truth for all dependency versions.

---

## Getting Started

Open `Code.xcodeproj` in Xcode 16.x. Swift packages resolve automatically on first open. Build and run the `Flipcash` scheme.

### Regenerating Protos

Swift gRPC bindings in `FlipcashAPI/Sources/FlipcashAPI/Payments/Generated` and `FlipcashAPI/Sources/FlipcashAPI/Core/Generated` are generated from `.proto` files pulled from the server-protobuf repos. To regenerate:

```
cd Scripts
./run -a flipcashPayments
./run -a flipcashCore
```

Each invocation clones the latest `.proto` files from the upstream repo, replaces the local `proto/` directory, and regenerates the Swift code in `Generated/`.

**Required tools** (checked by the script; aborts if missing):
- `protoc` — `brew install protobuf`
- `protoc-gen-swift` — `brew install swift-protobuf`
- `protoc-gen-grpc-swift-2` (grpc-swift **2.x**) — `./Scripts/install-grpc-swift-2-plugin.sh`

**Never modify files under `Generated/` directly** — changes will be overwritten on the next regen.

---

## Architecture & Patterns

### Design Pattern: MVVM + Container DI

```
Container (DI)
├── Client (gRPC)
├── FlipClient (Flipcash APIs)
├── AccountManager (Keychain)
└── SessionContainer (when logged in)
    ├── Session (main state, @Observable)
    ├── RatesController
    │   ├── VerifiedProtoService (actor – caches verified exchange rate + reserve state proofs)
    │   └── LiveMintDataStreamer (actor – bidirectional streaming for rates/reserves)
    ├── HistoryController
    └── Database (SQLite)
```

- **ViewModels** provide over multi-screen flows or complex navigation patterns but not necessary for standalone, self-contained, isolated screens.
- **Session** is the main state object after authentication
- **Controllers** handle business logic and data persistence

**Injected via the environment, not init prop-drilling.** `Container` and `SessionContainer` are both `@Observable` (the latter is a class) and injected with `.environment(self)` inside their `injectingEnvironment(from:)` helpers — `Container` at the app root (app-wide), `SessionContainer` on `ScanScreen` in `ContainerScreen`'s `.loggedIn` case (logged-in subtree). Read them with type-based `@Environment(Container.self)` / `@Environment(SessionContainer.self)`; sheets and `navigationDestination`s inherit them. A screen that builds its view model or seeds `@State` in `init` can't read `@Environment` there — split it into a thin env-reading wrapper (`struct X`) over an unchanged content view (`struct XContent`) whose `init` takes the deps. Reach for a granular env value (`@Environment(SessionAuthenticator.self)`, etc.) when a screen needs only one member; read the whole container otherwise.

### gRPC Call Options (v2)

Per-RPC deadlines are passed via `GRPCCore.CallOptions` on each call — there is no shared `CodeService` preset anymore. The v1 rule still holds in the v2 shape:

| RPC kind | Deadline | How |
|----------|----------|-----|
| **Unary** (request → response) | 15 seconds | pass `options: .unaryDefault` (defined in `GRPCTransport.swift`) |
| **Server-streaming / bidirectional** | None | pass nothing (`.defaults`) — a stray deadline silently kills long-lived streams |

Streaming RPCs run through the `BidirectionalGRPCStream` / `ServerGRPCStream` adapters in `GRPCStream.swift`, which bridge v2's closure-scoped streaming (`requestProducer:` / `onResponse:`) to a retained, multi-sender handle (`sendMessage` / `cancel`). The transport and the shared `UserAgentClientInterceptor` are configured once on the `GRPCClient` in `Client.swift` / `FlipClient.swift`; the `runConnections()` task must stay retained for the client's lifetime.

### Transport Failure Classification

A gRPC transport failure (request timeout / unavailable channel) is a network condition, not a code defect — it must never reach Bugsnag. The `TransportClassifiableError` protocol carries this guarantee.

- **Typed error enums:** conform the enum to `TransportClassifiableError` (give it a `.transportFailure` case — which `reportingLevel` maps to `.suppressed` — alongside `.unknown`), then in the call's `catch` map via `ErrorX.from(transportError: rpcError)`. The single shared `from(transportError: RPCError)` default does the mapping — you don't write one per enum. Never map a timeout to an `.error`-level `.unknown`.
- **Associated-value error enums** (cases like `.grpcStatus(RPCError)` / `.network(Error)`): return `.suppressed` from `reportingLevel` when the captured error is transient (`rpcError.code.isTransientNetworkError`), and forward `.grpcStatus(s)` / `.network(e)` to the inner value's `reportingLevel` (`(error as? ServerError)?.reportingLevel ?? .error`), mirroring `ErrorSubmitIntent` / `ErrorSwap` / `ErrorStatelessSwap` / `ErrorModeration`.
- **Unary RPCs whose failure type is the existential `Error`:** `RPCError` itself conforms to `ServerError`, mapping transient codes (`isTransientNetworkError`) to `.suppressed`, `.cancelled` to `.info` (app-initiated teardown, not a defect), and all other codes to `.error`, so shipping the raw error via `completion(.failure(error))` classifies transient transport failures automatically — no per-call-site mapping needed.
- `FlipcashCoreTests/TransportClassificationTests` asserts every conformer is wired — add a line when you add a classifiable error.

### Navigation: AppRouter

All navigation flows through `AppRouter` — a single `@Observable @MainActor` class on `SessionContainer`, injected via `@Environment(AppRouter.self)`. **Don't add screen-level `@State` sheet flags or `selectedXxx` bindings for navigation** — mutate the router instead. Deeplinks and push notifications call `router.navigate(to:)`; in-screen pushes call `router.push(_:on:)`.

Top-level sheets (`Balance`, `Settings`, `Give`, `Discover`) each own a `NavigationStack(path: $router[.<stack>])` and register destinations via the `.appRouterDestinations(...)` modifier on their root content. Per-stack paths are `NavigationPath` (type-erased), so sub-flow destinations (e.g., `WithdrawNavigationPath`, `BuyFlowPath`) coexist with top-level `Destination` cases on the same stack — register `.navigationDestination(for: SubFlowPath.self)` on the sub-flow root view and push via `router.pushAny(_:on:)`. **Don't nest a `NavigationStack` inside another stack's destination** — push/pop/push corrupts SwiftUI's stack state with `comparisonTypeMismatch`.

**Nested sheets.** `presentedSheets` is an ordered stack: `.first` is the root sheet (mounted at app root) and any entries above visually stack on top. Use `router.presentNested(.x(...))` to stack a sheet on top of the current top — required for "sheet over sheet" UX like buy-from-currency-info. SwiftUI requires nested sheets to be mounted from **inside** the parent sheet's content tree (sibling `.sheet` modifiers at the root can't stack), so each top-level sheet's content applies the `.appRouterNestedSheet(...)` modifier — that's the convention. New top-level sheets must remember to apply it; the modifier handles all nested levels via env-injected `nestedSheetDepth`. The buy flow is the only nested sheet today (`.buy(mint)`); sell/give/etc. are migrating opt-in.

**Local interaction sheets stay local.** Transient pickers (currency selection, funding selection) belong on the screen that owns them as `.sheet(...)` / `.fullScreenCover(...)` modifiers — they're interactions, not navigation. Operation-bound modals (swap/launch processing covers) similarly belong locally, *unless* they're part of a router-managed sheet's flow — in that case prefer pushing onto the sheet's stack as a `BuyFlowPath.processing` (or similar) so the sheet's dismiss tears down the whole chain.

**The test:** if a deeplink could reasonably land the user here, it's a destination — route through `AppRouter`. If not, keep it local.

**Sheet path lifecycle.** `dismissSheet` pops the topmost sheet and leaves its `NavigationPath` populated so the closing animation runs with current contents. The path is cleared on the next `present(_:)` or `presentNested(_:)` of that same sheet value, so re-opens land at root. Sheet swaps at root (`present(.different)` without an intervening `dismissSheet`) preserve the swapped-out root's path for swap-back; nested sheets above a swapped root are always dismissed (and their paths cleared on re-open). `present(.sameRoot)` while a nested sheet is up pops the nested and keeps the root path. Don't add manual `popToRoot` calls around your own dismissal — let the router handle it.

Every router mutation logs one INFO entry under `flipcash.router` — filter by that label to trace any navigation interaction.

### Key Architectural Concepts

1. **Quarks** - Smallest unit of any currency (like cents for dollars)
2. **ExchangedFiat** - Wraps underlying currency + converted display value
3. **BondingCurve** - Pricing for custom currencies
4. **AccountCluster** - Manages keys per mint
5. **VerifiedState** - Bundles server-signed exchange rate proof (`rateProto`) and optional reserve state proof (`reserveProto`). Required when submitting any payment intent. For **launchpad currencies**, `reserveProto` is mandatory — the server rejects intents without it. **Pin-at-compute invariant**: amount-entry flows (`CurrencyBuyViewModel`, `CurrencySellViewModel`, `WithdrawViewModel`, `GiveViewModel`) fetch the pin at the commit moment via `prepareSubmission()` and compute `ExchangedFiat.quarks` against that same pin. The pin is then carried through `Session.showCashBill` → `BillDescription.verifiedState` → `SendCashOperation` / `createCashLink` so face-to-face transfer and cash-link submission both use the proof the quarks were derived from. Fetching twice or pinning at flow-open reintroduces the "native amount and quark value mismatch" reject.
6. **SendCashOperation** - Orchestrates peer-to-peer transfers via a rendezvous handshake. Has two concurrent paths: Path 1 (advertise bill with verified state) and Path 2 (listen for grab, then transfer). Both paths share a resolved `VerifiedState`.

---

## Technology Stack

### Required Technologies

| Technology | Version/Notes |
|------------|---------------|
| Swift | 6.0 (language mode); Xcode toolchain 16.x |
| iOS Minimum | 18.0 |
| UI Framework | SwiftUI (primary), UIKit (AppDelegate, navigation) |
| Testing | Swift Testing (`import Testing`) |
| Database | SQLite via SQLite.swift (fork, see below) |
| Networking | gRPC via grpc-swift 2 (GRPCCore + Network.framework TransportServices) |
| Crypto | Ed25519 via CodeCurves |

### Package Structure

```
Flipcash/          # Main app - focus here
FlipcashCore/      # Business logic, models, clients
FlipcashUI/        # UI components, theme
FlipcashAPI/       # gRPC proto definitions + generated v2 bindings (Payments/ + Core/)
CodeCurves/        # Ed25519 cryptography
CodeScanner/       # C++/OpenCV circular code scanning (see below)
```

### SQLite.swift Fork

**We use a fork of SQLite.swift** (`dbart01/SQLite.swift`), not the official `stephencelis/SQLite.swift`. The fork is pinned to `master` branch and adds two changes on top of the official `0.15.4` base:

1. **Upsert WHERE clause fix** — moves `whereClause` after `DO UPDATE SET` (the official repo places it before `ON CONFLICT`, producing invalid SQL for filtered upserts like `table.filter(...).upsert(...)`)
2. **Custom dispatch queue injection** — adds a `queue:` parameter to `Connection.init` so callers can supply their own `DispatchQueue`
3. **Public `Setter` access (pending)** — `Setter.column` and `Setter(excluded:)` need to be made `public` so callers can build custom ON CONFLICT SET clauses (e.g., `COALESCE(excluded.column, column)` for conditional upserts). See `Database+Balance.swift` TODO.

**Do not switch to the official repo** without verifying:
- Filtered upserts still generate valid SQL
- `Connection.init(queue:)` is no longer needed
- Custom SET clause building still compiles

---

## CodeScanner Project

C++ library for encoding, decoding, and scanning custom circular 2D codes ("Kik Codes"). Uses OpenCV 4.10.0 and a bundled ZXing Reed-Solomon subset.

- **Location:** `CodeScanner/`
- **Public API:** `CodeScanner/CodeScanner/Code.h` (`KikCodes` class — encode, decode, scan)
- **Used by:** `CodeExtractor.swift`, `CashCode.Payload+Encoding.swift`
- **Full spec:** `.claude/spec.md` (API details, build docs, OpenCV upgrade history)
- **Updating OpenCV:** `cd CodeScanner && ./Scripts/build_opencv.sh --version <version>`

---

## Code Style & Conventions

### File Organization

- Screens go in `Flipcash/Core/Screens/`
- ViewModels are colocated with their screens
- Models go in `FlipcashCore/Sources/FlipcashCore/Models/`
- Database models go in `Flipcash/Core/Controllers/Database/Models/`

### Naming Conventions

- ViewModels: `{Screen}ViewModel` (e.g., `GiveViewModel`)
- Screens: `{Name}Screen` (e.g., `ScanScreen`)
- Controllers: `{Domain}Controller` (e.g., `RatesController`)

### Import Order

```swift
import SwiftUI       // System frameworks first
import FlipcashCore  // Then internal packages
import FlipcashUI
```

### Avoid Over-Engineering

- Don't add features beyond what was asked
- Don't add error handling for impossible scenarios
- Don't create abstractions for one-time operations
- Don't add comments to code you didn't change
- Three similar lines of code is better than a premature abstraction

---

## Testing

### Framework: Swift Testing

```swift
import Testing
@testable import Flipcash

@Suite("Session Tests")
struct SessionTests {

    @Test("Sufficient funds returns correct amount")
    func sufficientFunds() {
        // Arrange
        let session = makeTestSession()

        // Act
        let result = session.hasSufficientFunds(for: amount)

        // Assert
        #expect(result == .sufficient(amount))
    }
}
```

### Running the App & Tests

Use the project scripts — they encode the correct scheme and destination:

- **Build the app:** `./Scripts/build.sh` (generic iOS) or `./Scripts/build.sh --device` (paired physical iPhone)
- **Targeted tests (for your changes):** `./Scripts/test.sh <Target>/<Suite>[/<TestName>] [...]` — always runs on the iPhone 17 simulator
  - One suite: `./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests`
  - Multiple suites: `./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests FlipcashCoreTests/FiatTests`
  - One test: `./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests/myTestCase`
- **Full `AllTargets` suite is the user's job** — don't run it. If you think it's required before declaring work done, ask the user to run it.

**Never run `swift test` in a package directory** (`FlipcashCore`, `FlipcashUI`, etc.). Packages are iOS-only; `swift test` targets the macOS host and fails with code-signing errors. Always go through `./Scripts/test.sh` (which routes through the `Flipcash` scheme on the iOS Simulator).

For paired-device builds, see [Xcode MCP Server](#xcode-mcp-server) below.

### Test Naming

- Use descriptive names that explain the scenario
- Format: `func methodName_scenario_expectedResult()` paired with `@Test("description")` for the display name

### Test the Actual Implementation

**NEVER recreate functionality in tests.** Always test the actual implementation:

```swift
// ❌ BAD: Recreates the logic, proves nothing about the real code
@Test func testTotalBalance() {
    let sum = balance1.converted.decimalValue + balance2.converted.decimalValue
    let total = Quarks(fiatDecimal: sum, ...)
    #expect(total.formatted() == "$8.10")  // Tests nothing real
}

// ✅ GOOD: Tests the actual Session.totalBalance implementation
@Test func testTotalBalance() {
    let session = makeTestSession(balances: [balance1, balance2])
    let total = session.totalBalance
    #expect(total.converted.formatted() == "$8.10")
}
```

If the code under test is difficult to call directly, create test support extensions or mock dependencies rather than duplicating the logic.

### Test Support Extensions

**Keep production code clean** - test-only helpers belong in the test target:

```swift
// ❌ BAD: Adding #if DEBUG to production code
// Flipcash/Core/Controllers/RatesController.swift
#if DEBUG
func configureTestRates(...) { ... }
#endif

// ✅ GOOD: Extension in test target
// FlipcashTests/TestSupport/RatesController+TestSupport.swift
extension RatesController {
    func configureTestRates(...) { ... }
}
```

Place test support extensions in `FlipcashTests/TestSupport/` using the naming pattern `{Type}+TestSupport.swift`.

### CI Compatibility

**All tests must work on both Xcode Cloud and locally.** Never use APIs that are sandboxed or unavailable on Xcode Cloud:

- ❌ `Process` / `ProcessInfo` for shelling out (sandboxed on Xcode Cloud)
- ❌ `xcrun simctl` from within tests
- ❌ Host-only filesystem access
- ✅ `UIPasteboard`, `XCUIApplication`, `XCUIElement` — standard XCUITest APIs

### Regression Tests

**Every crash fixed from Bugsnag (or similar) gets a dedicated regression test** in `FlipcashTests/Regressions/`.

- **One file per incident:** `Regression_{bugsnag_id}.swift`
- **Suite name includes the short ID:** `@Suite("Regression: {short_id} – {brief description}")`
- **Reproduce the crash path**, not just the low-level fix. If the crash came through `EnterAmountCalculator`, test through `EnterAmountCalculator`.

```swift
// FlipcashTests/Regressions/Regression_698ef3b65e6cc4bb5554e13d.swift

@Suite("Regression: 698ef3b – Quarks comparison overflow for high-rate currencies")
struct Regression_698ef3b {

    @Test("CLP quarks comparison across 6 and 10 decimal precisions does not overflow")
    func quarksComparison_CLP_doesNotOverflow() { ... }
}
```

---

## Git & Workflow

### Commit Messages

```
<type>: <short description>

<optional body explaining why>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

### Before Committing

1. Code compiles without errors and no new warnings: `./Scripts/build.sh`
2. Targeted tests pass for the changed areas: `./Scripts/test.sh <your-suites>` — the user runs the full `AllTargets` suite themselves before approving the commit
3. Review changes with `git diff`
4. Switch statements are exhaustive (no unnecessary `default` cases)
5. Changes are minimal and focused on the task

---

## Common Pitfalls

| Pitfall | Solution |
|---------|----------|
| Modifying generated proto files | Update service files instead |
| Adding unnecessary abstractions | Keep it simple, solve the current problem |
| Completing a transaction without refreshing balances | Call `session.updatePostTransaction()` after any transaction completes |
| Canceling/modifying `SendCashOperation` in `dismissCashBill` | **Never** explicitly call `cancel()` or `invalidateMessageStream()` on `SendCashOperation` from `dismissCashBill`. After a grab, the received bill is a **live** `SendCashOperation` that others can scan ("quick give and grab" chain). Setting `sendOperation = nil` is fine (deinit cleans up), but explicit teardown kills a live bill. The operation's `complete()` method handles stream teardown on success/failure. |
| Giving a streaming RPC a deadline | Streaming RPCs (`openMessageStream`, `submitIntent`, `streamLiveMintData`, `statefulSwap`) run through the `BidirectionalGRPCStream`/`ServerGRPCStream` adapters with NO per-call deadline (`.defaults`). A stray deadline silently kills long-lived streams. See [gRPC Call Options](#grpc-call-options). |
| Showing a received bill without `verifiedState` | Every call to `showCashBill` must pass `verifiedState` — even for `received: true` bills. The received bill creates a live `SendCashOperation` for the "quick give and grab" chain. Without `verifiedState`, launchpad currency transfers fail with "reserve state is required". Both `receiveCash` (scan) and `receiveCashLink` (deep link) must provide it. |
| Nesting a `NavigationStack` inside another stack's destination | Crashes with `SwiftUI.AnyNavigationPath.Error.comparisonTypeMismatch` on push/pop/push. Drop the inner stack; register `.navigationDestination(for: SubFlowPath.self)` on the destination's root view and push sub-flow steps via `router.pushAny(_:on:)`. The parent stack's `NavigationPath` carries both the typed `Destination` cases and the sub-flow's Hashable values. |
| Cross-stack `navigate(to:)` shows stale leaf data | When two destinations have the same case but different associated values (e.g., `.currencyInfo(A)` → `.currencyInfo(B)`), SwiftUI keeps the existing view at the same path depth and `@State` survives — the leaf renders with old data. Add `.id(value)` to the destination view in `DestinationView` so each value forces a fresh view identity. |
| `matchedGeometryEffect` applied after `.frame` | **`.matchedGeometryEffect` must come BEFORE `.frame` in the modifier chain.** Wrong order causes hero animations to fail silently: you see two separate views fading in/out at their own static positions instead of one morphing element. Paul Hudson's hackingwithswift example uses the wrong order and does not work on current iOS. Correct: `Rectangle().fill(.red).matchedGeometryEffect(id:in:).frame(width:height:)`. Incorrect: `Rectangle().fill(.red).frame(width:height:).matchedGeometryEffect(id:in:)`. Also note: `.transition(.identity)` on a parent containing matched views **kills the animation entirely** — matched geometry needs the parent view to remain in the tree briefly for interpolation, and `.identity` removes it instantly. |
| Binding the same `dialogItem` to `.dialog(item:)` on two views in the live hierarchy | `dialog(item:)` is `.sheet(item:)` under the hood (`Dialog+View.swift`). When two views in the live tree bind the same observable — e.g. `ScanScreen` *and* a sheet `ScanScreen` is currently presenting — both attempt to present the dialog, and UIKit logs `Currently, only presenting a single sheet is supported`. For dialogs that need to fire across sheet boundaries (a viewmodel referenced by both `ScanScreen` and a router-presented sheet, or an error that fires *while* a sheet is being torn down), route through `session.dialogItem`. `DialogWindow` hosts that binding in a separate `UIWindow` at `UIWindow.Level.alert` and renders above every sheet without joining the main window's presentation queue. Per-screen state that's only ever bound by one view in the tree (e.g. a `@State DialogItem?` on a leaf) is fine to keep local. |
| Calling `router.present(.x)` next to a viewmodel mutator that may *block* the flow | A viewmodel that surfaces a blocking error via `session.dialogItem` (e.g. `GiveViewModel.showNoBalanceError`) does not stop the router — `DialogWindow` renders the dialog above the sheet, but the sheet is still presented underneath and reappears once the dialog is dismissed. Gate the router on the precondition: expose `attemptPresent() -> Bool` on the viewmodel and write `if vm.attemptPresent() { router.present(.x) }`. Putting the check inside an `isPresented` `didSet` is not enough — the router call still runs unconditionally on the next line. |
| Parsing keypad-emitted amounts with `Decimal(string:)` or `NumberFormatter.decimal(from:)` | `KeyPadView`'s decimal key inserts `Metrics.localizedDecimalSeparator`, so on comma-decimal locales the bound string contains ",". `Decimal(string:)` stops at the comma and silently drops the fraction; `NumberFormatter.decimal(from:)` only parses the device locale's format. **Parse keypad strings with `KeyPadView.amount(from:)`** — it normalizes the locale separator before parsing. `NumberFormatter.decimal(from:)` remains appropriate for currency-formatted strings (already through a formatter, locale-correct). |
| Injecting shared DI via a custom keyPath `@Environment(\.key)` with a trapping default | SwiftUI resolves keyPath env **eagerly** during dynamic-list/transition `DynamicProperty` updates (against a placeholder environment), so a `fatalError`/`preconditionFailure` default fires and crashes at launch (`<dep> was not injected`). Inject shared DI as **type-based `@Environment(Type.self)` on an `@Observable`** — the trap is deferred to body access, so it survives the eager pass. That's why `Container`/`SessionContainer` are `@Observable`. Safe-value `@Entry` keyPath defaults (e.g. `nestedSheetDepth = 0`) are unaffected — the hazard is specifically a *crashing* default. |

---

## Quick Reference

### Key Files

```
Navigation:
- Flipcash/Core/Navigation/AppRouter.swift (class + mutators + logging)
- Flipcash/Core/Navigation/AppRouter+Destination.swift (push targets)
- Flipcash/Core/Navigation/AppRouter+SheetPresentation.swift (top-level sheets)
- Flipcash/Core/Navigation/AppRouter+Stack.swift (per-sheet stacks)
- Flipcash/Core/Navigation/AppRouter+DestinationView.swift (destination → view map)
- Flipcash/Core/Navigation/AppRouter+NestedSheet.swift (nested sheet modifier + root views)

Session & Auth:
- Flipcash/Core/Session/Session.swift
- Flipcash/Core/Session/SessionAuthenticator.swift

Payments & Operations:
- Flipcash/Core/Screens/Main/Operations/SendCashOperation.swift
- Flipcash/Core/Screens/Main/Operations/ScanCashOperation.swift
- FlipcashCore/Sources/FlipcashCore/Models/VerifiedState.swift
- FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Services/VerifiedProtoService.swift

Onramp & Coinbase:
- Flipcash/Core/Controllers/Onramp/OnrampCoordinator.swift
- Flipcash/Core/Controllers/Onramp/OnrampHostModifier.swift
- Flipcash/Core/Screens/Onramp/OnrampAmountScreen.swift (buy-existing amount entry only)

Multi-Currency:
- FlipcashCore/Sources/FlipcashCore/Models/Fiat.swift (Quarks)
- FlipcashCore/Sources/FlipcashCore/Models/ExchangedFiat.swift
- FlipcashCore/Sources/FlipcashCore/Models/BondingCurve.swift

Rates & Streaming:
- Flipcash/Core/Controllers/RatesController.swift
- FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Services/LiveMintDataStreamer.swift

Database:
- Flipcash/Core/Controllers/Database/Schema.swift
- Flipcash/Core/Controllers/Database/Database.swift
```

### Key Constants

```swift
// USDC
PublicKey.usdc // Main stablecoin mint
PublicKey.usdc.mintDecimals // 6

// Bonding Curve
BondingCurve.startPrice  // $0.01
BondingCurve.endPrice    // $1,000,000
BondingCurve.maxSupply   // 21,000,000 tokens
```

### Xcode MCP Server

**Prefer Xcode MCP tools over `xcodebuild` shell commands** when the Xcode MCP server is available. It provides direct integration with the open Xcode workspace for building, testing, reading/writing project files, rendering SwiftUI previews, and searching Apple documentation.

**Fall back to `./Scripts/build.sh` and `./Scripts/test.sh`** when the MCP server is not connected. See [Running the App & Tests](#running-the-app--tests) for usage. For edge cases the scripts don't cover (e.g., a one-off destination, `xcodebuild clean`), drop down to raw `xcodebuild`.

**Device builds.** XcodeBuildMCP ships device tools (`build_device`, `build_run_device`, `test_device`, `list_devices`, etc.) in its `device` workflow. They're available whenever `device` is in the `XCODEBUILDMCP_ENABLED_WORKFLOWS` list in your `.mcp.json` (that file is per-developer and gitignored — add `device` to the comma-separated list to turn them on). Use device tools the same way as the simulator ones. If they're not present (workflow not enabled, or the MCP server hasn't reloaded its config), silently fall back to `./Scripts/build.sh --device` — **never narrate which path you took.**

When you need to confirm a paired iPhone, use the `list_devices` MCP tool (or `xcrun devicectl list devices`). **Do not use `xcrun xctrace list devices`** — it mislabels paired iPhones as `Offline` and will lead you to falsely claim no device is connected.

If the user says "build on my device," take them at their word and just do it — don't push back claiming only simulators are available. Tests remain simulator-only.
