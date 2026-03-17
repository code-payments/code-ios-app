# UI Smoke Tests Implementation Plan

**Goal:** Set up a UI smoke test suite that validates critical flows (login, account creation, main screen) using XCUITest, with secure access key injection via xcconfig.

**Architecture:** The app detects a `--ui-testing` launch argument to disable animations, skip analytics/error reporting initialization, wipe UserDefaults, and call `logout()`. The UI test target reads a `UITestAccessKey` from `Info.plist` (injected via `secrets.local.xcconfig`) and opens the login deep link via `XCUIApplication.open(_:)`. Tests query elements by accessibility labels (not identifiers) to enforce real accessibility.

**Tech Stack:** XCUITest (XCTest), launch arguments, xcconfig secrets, existing deep link infrastructure.

**Important:** UI tests use XCTest, not Swift Testing. This is the one exception to the CLAUDE.md rule — Swift Testing has no UI automation support.

---

## File Structure

```
FlipcashUITests/
├── Support/
│   └── BaseUITestCase.swift         # Shared setUp, helpers, login via deep link, app launch config
├── Smoke/
│   ├── LoginSmokeTests.swift        # Login via access key, verify main screen
│   └── CreateAccountSmokeTests.swift # Account creation flows (save to photos, wrote down)
├── Info.plist                        # UITestAccessKey from xcconfig
├── FlipcashUITests.swift            # (cleaned up — header only)
└── FlipcashUITestsLaunchTests.swift # (cleaned up — header only)

Flipcash/
└── Core/
    └── AppDelegate.swift            # --ui-testing: disable animations, skip analytics, reset state

Configurations/
└── secrets.xcconfig                 # FLIPCASH_UI_TEST_ACCESS_KEY placeholder
```

---

## Implemented

### AppDelegate `--ui-testing` block

When `--ui-testing` is detected:
1. **Skip** `Analytics.initialize()` and `ErrorReporting.initialize()` — avoids sending test events to production services and reduces startup latency
2. **Disable animations** via `UIView.setAnimationsEnabled(false)`
3. **Call `logout()`** — resets keychain pointers, auth state, UserDefaults flags, tears down push/rates controllers

### BaseUITestCase

Shared base class providing:
- `app.launchArguments = ["--ui-testing"]`
- `requiresAuthentication` override for login-dependent tests
- `resetPermissions` override for per-test permission resets
- `waitAndTap(_:timeout:_:)` — asserts existence then taps, reduces boilerplate
- `assertMainScreenReached(timeout:_:)` — waits for the "Give" button as the main screen indicator
- Access key read from `Info.plist` → `UITestAccessKey` (injected via `FLIPCASH_UI_TEST_ACCESS_KEY` in xcconfig)
- `XCTSkipIf` when access key is missing — tests skip gracefully, don't fail

### Access Key Injection

- `Configurations/secrets.xcconfig` has `FLIPCASH_UI_TEST_ACCESS_KEY = xxx` placeholder
- Developers override in `secrets.local.xcconfig` with their real key
- `FlipcashUITests/Info.plist` maps `UITestAccessKey` → `$(FLIPCASH_UI_TEST_ACCESS_KEY)`
- `BaseUITestCase` reads from the test bundle's `infoDictionary`

### Smoke Tests

| Test | File | Auth Required | What It Verifies |
|------|------|--------------|------------------|
| `testLoginViaAccessKey_reachesMainScreen` | `LoginSmokeTests.swift` | Yes | Deep link login reaches ScanScreen (Give + Wallet buttons) |
| `testCreateAccount_saveToPhotos` | `CreateAccountSmokeTests.swift` | No | Full account creation flow via "Save to Photos" |
| `testCreateAccount_wroteDownInstead` | `CreateAccountSmokeTests.swift` | No | Account creation via "Wrote Down" confirmation |

---

## Future Tests to Consider

- **GiveSmokeTests** (authenticated): Tap "Give" button, verify give sheet opens with "Next" button
- **WalletSmokeTests** (authenticated): Tap "Wallet" button, verify wallet sheet opens with "Wallet" nav title
- **Cash link test**: Open `flipcash://c#e=...` deep link while logged in, verify the receive UI appears
- **Settings test**: Tap the hamburger menu, verify settings sheet opens

### What NOT to Test in Smoke Tests

- Actual monetary transactions (send, receive, claim)
- Server-dependent flows that modify state
- Flows that require real camera input
