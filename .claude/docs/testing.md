# Testing

## Framework: Swift Testing

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

## Running the App & Tests

Use the project scripts — they encode the correct scheme and destination:

- **Build the app:** `./Scripts/build.sh` (generic iOS) or `./Scripts/build.sh --device` (paired physical iPhone)
- **Targeted tests (for your changes):** `./Scripts/test.sh <Target>/<Suite>[/<TestName>] [...]` — always runs on the iPhone 17 simulator
  - One suite: `./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests`
  - Multiple suites: `./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests FlipcashCoreTests/FiatTests`
  - One test: `./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests/myTestCase`
- **Full `AllTargets` suite is the user's job** — don't run it. If you think it's required before declaring work done, ask the user to run it.

### Test plans

- **`AllTargets`** (scheme default) — all three test targets, no sanitizers. `Scripts/test.sh`
  passes no `-testPlan`, so targeted runs land here.
- **`Sanitizers`** — `FlipcashTests` + `FlipcashCoreTests` under Thread Sanitizer:
  `xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -testPlan Sanitizers`

**`Sanitizers` cannot currently pass.** The TSan runtime aborts the host partway through and
xcodebuild marks everything in flight as failed, so the run exits 65 with hundreds of failures and
no race report. Those failures are casualties, not findings — they all report `(0.000 seconds)`
and record no issue. Neither target completes alone, so there is no narrower scope that works. The
release checklist runs it as an advisory step and reads only the race count; see
[the release skill](../skills/release/SKILL.md) step 6a for the classification commands.

TSan came off the UI tests first, where its runtime crashes during XCUITest's accessibility
snapshots. The crash is inside the sanitizer, not app code, in both cases. Details, evidence, and
repro steps in [2026-08-25-tsan-ui-test-crash.md](../plans/2026-08-25-tsan-ui-test-crash.md).
Don't move TSan back onto `AllTargets` without re-checking that analysis against the current Xcode.

**Never run `swift test` in a package directory** (`FlipcashCore`, `FlipcashUI`, etc.). Packages are iOS-only; `swift test` targets the macOS host and fails with code-signing errors. Always go through `./Scripts/test.sh` (which routes through the `Flipcash` scheme on the iOS Simulator).

For paired-device builds, see [Xcode MCP Server](quick-reference.md#xcode-mcp-server).

## Test Naming

- Use descriptive names that explain the scenario
- Format: `func methodName_scenario_expectedResult()` paired with `@Test("description")` for the display name

## Test the Actual Implementation

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

## Test Support Extensions

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

## CI Compatibility

**All tests must work on both Xcode Cloud and locally.** Never use APIs that are sandboxed or unavailable on Xcode Cloud:

- ❌ `Process` / `ProcessInfo` for shelling out (sandboxed on Xcode Cloud)
- ❌ `xcrun simctl` from within tests
- ❌ Host-only filesystem access
- ✅ `UIPasteboard`, `XCUIApplication`, `XCUIElement` — standard XCUITest APIs

## Regression Tests

**Every crash fixed from Bugsnag (or similar) gets a dedicated regression test** in `FlipcashTests/Regressions/`, reproducing the crash path and **observed failing on the unfixed code first**. Naming, suite conventions, and the false-green traps (windowing, live-cell reads) live in [`.claude/skills/triage/references/regression-tests.md`](../skills/triage/references/regression-tests.md).
