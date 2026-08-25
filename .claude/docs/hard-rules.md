# Hard Rules (Non-Negotiable)

The full text, rationale, and examples for every non-negotiable rule. The condensed
checklist lives in [`CLAUDE.md`](../../CLAUDE.md#hard-rules-non-negotiable) — read this file
for the "why" and the code examples before touching the relevant area.

## Comments: Document the API, Constrain the Implementation

Non-private API carries a `///` doc comment in Apple's style: one third-person sentence stating the contract — what it returns or does for the caller — never the mechanism. Inline comments state only non-obvious constraints, one sentence, never repeating a rationale within the file.

## State Lives in Named Units

A concern that owns **more than two pieces of state** (flags, tasks, queues, deadline maps) gets its own type — `@MainActor @Observable` class for UI-bound state, `actor` for cross-domain state — composed as a single `let` on the owner with thin forwards. Never loose fields accreted onto a shared controller. Judge by the concern's **total** field count at the end of the change, not the per-edit delta; extraction is part of the change itself, not a follow-up. Example: `ConversationTyping` owns all typing state; `ConversationController` holds one `let typing` and forwards.

## Testing Framework

**Use Swift Testing, NOT XCTest:**

```swift
// ❌ WRONG
import XCTest
class MyTests: XCTestCase { ... }

// ✅ CORRECT
import Testing
@Suite struct MyTests { ... }
```

## Exhaustive Switch Statements

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

## Modernize Incrementally

**When writing new code or touching isolated screens, prefer modern Swift/SwiftUI APIs.** This is a gradual migration — don't refactor working code just to modernize it, but do use modern patterns in net-new or self-contained work.

| Legacy | Modern | Notes |
|--------|--------|-------|
| `ObservableObject` / `@Published` | `@Observable` | Use `@State` in views instead of `@StateObject` |
| `@EnvironmentObject` | `@Environment` | For new dependencies; existing `@EnvironmentObject` stays until the injected type is migrated |
| `@AppStorage` wrapping `UserDefaults` manually | `@AppStorage` directly | For simple per-screen preferences |
| `onChange(of:perform:)` (deprecated) | `onChange(of:initial:_:)` | Use `initial: true` when the handler should also fire on appear |

Existing `ObservableObject` classes (`Client`, `FlipClient`) stay as-is until their dependents are migrated. A single class must use one system — either `ObservableObject` with `@Published`, or `@Observable`. Mixing causes silent observation failures.

## Generated Protos

**Generated proto code is not in this repo.** `FlipcashAPI` re-exports `OCPClientProtocol` and
`Flipcash2ClientProtocol`, which are published from their own repos (see
[Protos: consumed, not generated here](technology-stack.md#protos-consumed-not-generated-here)).
A contract fix belongs in the package repo and reaches the app as a version bump; anything the
app can fix itself belongs in the service files that wrap the generated code.

## Database Schema Changes

**Bump `SQLiteVersion` in Info.plist on every schema change.** The app does not run migrations — when the version number increases, the database is deleted and rebuilt from server data on next login (`SessionAuthenticator.initializeDatabase`). This means:

- Adding/removing tables or columns → bump version
- Changing which table a query reads from → bump version if the old schema can't satisfy the new query
- No migration code needed, but all data must be recoverable from server

## Logging: Variables Go in Metadata

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

## Error Reporting: Always Call `captureError` Unconditionally

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

**Best-effort chatter never reports at all.** `captureError` is for failures a developer should act on. Fire-and-forget UX signals (typing indicators and similar presence-style traffic, which the proto marks droppable) log at most one warning per burst and do **not** call `captureError` — a failed typing notification is not actionable.

## Form Input Validation: Use the `Validator` Family

**Validate free-form input through `Validator` (in `FlipcashCore/Sources/FlipcashCore/Validation/`), not inline regex/trim/length checks.** Each input type gets a concrete validator (`EmailValidator`, `PhoneValidator`, `CurrencyNameValidator`, `LengthValidator`, `AmountValidator`) that owns the rule, returns the canonical form, and is unit-testable in isolation.

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

**Entered amounts are not an exception.** Any string bound to `KeyPadView`/`EnterAmountView` is parsed exclusively by `AmountValidator`. This exact bug shipped twice — the older amount flows were fixed to parse locale-aware, then a newer flow reached for `Decimal(string:)` again and silently dropped the fraction on comma-decimal locales on a real-money path (PR #448). When adding or touching an amount-entry flow, run `rg "Decimal\(string:" Flipcash/` — the only legitimate hits parse machine-formatted strings (round-trips of `Decimal.description`, server payloads), never anything a user typed.

## Money & Numbers: The Nine Rules

Two real-money bugs shipped on 2026-07-08 from the same disease — a number displayed one way and compared another (a 1.00 CAD balance that couldn't buy 1.00 CAD; a "$7.08 minimum" dialog that rejected $7.08). The narrow rule written after the first bug named the *scenario* (balances) and missed the second (a threshold). These rules name the *class*. Full audit with per-finding evidence: `.claude/plans/2026-07-08-number-handling-audit.md` (local). Known pre-existing violations are catalogued there (§8) — fix them when touched; never add new ones.

1. **Money lives in exactly three types:** `TokenAmount` (on-chain), `FiatAmount` (fiat), `ExchangedFiat` (the bridge). Read `.value`/`.quarks` only at edges (formatting, DB write, wire encode) — never for arithmetic or comparison at a call site. Arithmetic goes through the types' checked operators.

2. **One parse in, one serialization out.** User input parses only via `AmountValidator`. Money round-tripped as a string is `Decimal.description` ↔ `Decimal(string:)`, nothing else.

3. **One format out.** Every user-visible money string comes from `FiatAmount.formatted(...)`. Numbers leaving the app (Coinbase, any external API) are explicitly formatted to the target's precision — raw `Decimal` interpolation onto a wire is forbidden.

4. **Comparisons happen in exactly two domains.** *Truth:* quarks vs quarks (`TokenAmount` is `Comparable`). *Promise:* display-rounded native vs display-rounded native — anything a user was shown. Never compare across an FX conversion; never compare an unrounded converted `Decimal` to anything.

5. **What we display is what we accept.** Any bound shown to a user (balance, limit, minimum, fee floor) is rounded to display precision *first*; that same rounded value is displayed and compared. See `CoinbaseDepositOperation.checkMinimum` for the canonical shape.

6. **Rounding modes are fixed per boundary:** fiat→quarks = HALF-UP (`scaleUpInt`, Kotlin parity); bonding-curve math = HALF-EVEN internal, exits only via `ExchangedFiat.compute`; display = the formatter; displayed bounds = rule 5; persisted/wire strings = no rounding (`Decimal.description`). A new rounding call site must name its boundary.

7. **Quarantine `Double` at the edges.** Proto Double/Float values convert to the wrapper types once, at decode; `.doubleValue` appears only inside intent encoders and analytics. New DB columns for money are `Decimal.description` strings, never `Double`.

8. **One copy of each concept.** FX synthesis lives in `ExchangedFiat`; fee scaling in `subtractingFee`; "smallest displayable unit" in `FiatAmount`. Hand-rolling any of these at a call site is a bug even when the math is right.

9. **Every affordability gate goes through `Session.hasSufficientFunds(for:)`** (quarks compare + half-denomination tolerance), and every user-entered spend amount is computed with the balance cap — `ExchangedFiat.compute(fromEntered:..., balance:, tokenBalanceQuarks:)`. No flow invents its own domain or its own tolerance.

```swift
// ❌ BAD: raw fiat compare — display rounding rejects a visible max-spend
return balance.usdf.value >= amount.usdfValue.value

// ✅ GOOD: the canonical gate, then the balance-capped compute (see GiveViewModel)
switch session.hasSufficientFunds(for: enteredFiat) {
case .sufficient: ...
case .insufficient(let shortfall): ...
}
ExchangedFiat.compute(
    fromEntered: native, rate: pin.rate, mint: .usdf,
    supplyQuarks: 0, balance: session.balance(for: .usdf)?.usdf
)
```

## Package.resolved Policy

**Always commit the workspace Package.resolved:**

- ✅ `Code.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` - MUST be committed
- ❌ Individual package `Package.resolved` files - ignored by git

This ensures deterministic builds across all developers and CI systems while minimizing merge conflicts. The workspace Package.resolved is the single source of truth for all dependency versions.
