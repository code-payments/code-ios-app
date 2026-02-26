# CodeButton Removal Plan

Goal: completely remove `CodeButton` from the Flipcash module and eventually from FlipcashUI.

---

## Completed

### PR #118 — FilledButtonStyle + SwapProcessingScreen
- Added `FilledButtonStyle` with `.filled`, `.filled50`, `.filled20`, `.filled10` presets
- Migrated `SwapProcessingScreen` (including `.successText` state → label with checkmark)

### PR #119 — Adopt across simple screens
- 10 screens migrated: all `CodeButton(style: .filled)` with no `state`/`disabled` params
- Also migrated `.filledCustom` in `FundingSelectionSheet` (icon moved to label)

---

## Scope

### What lives where

| Item | Location | Public | Used by |
|------|----------|:------:|---------|
| `CodeButton` | FlipcashUI | Yes | Flipcash (21 files), Code (38 files), Flipchat (22 files), FlipcashUI (1 file) |
| `ButtonState` | FlipcashUI/Views/Buttons/ButtonState.swift | Yes | CodeButton, CapsuleButton, DialogButton, + 47 refs in Flipcash/Code/Flipchat ViewModels |
| `CodeButton.Style` | Nested in CodeButton | Yes | Only used at CodeButton call sites |
| `LoadingView` | FlipcashUI | Yes | CodeButton, CapsuleButton, DialogButton, SwipeControl, Row, Loadable, etc. |
| `Metrics.button*` | FlipcashUI/Metrics.swift | Yes | CodeButton, DialogButton, Banner, FilledButtonStyle |

### What can be deleted vs. what stays

- **Delete**: `CodeButton.swift` and `CodeButton.Style` — no other component depends on them internally
- **Keep**: `ButtonState` — used by `DialogButton`, `CapsuleButton`, and throughout ViewModels
- **Keep**: `LoadingView` — used by many components beyond CodeButton
- **Keep**: `Metrics.button*` — used by other components and FilledButtonStyle

---

## Phase 1: New ButtonStyle presets

Before migrating the remaining screens, `FilledButtonStyle` needs these additions:

### `.filledSecondary` (2 usages)
- CurrencyInfoScreen: "View Transaction History", "Sell"
- Needs: material background (`.ultraThinMaterial`) + `.white.opacity(0.2)` overlay
- Implementation: add `usesMaterialBackground: Bool` flag to `FilledButtonStyle`

### `BorderedButtonStyle` (used in Code/Flipchat, not in Flipcash currently)
- Stroke border, no fill
- Already designed in commit `7599cfd` — bring it in when needed

### `SubtleButtonStyle` (6 usages in Flipcash)
- PermissionScreen: "Not Now"
- PurchasePendingScreen: "Cancel Purchase"
- IntroScreen: "Log In"
- AccountSelectionScreen: "Enter a Different Access Key"
- FundingSelectionSheet: "Dismiss"
- AccessKeyScreen: "Wrote the 12 Words Down Instead?"
- Needs: no background, `.textMain.opacity(0.6)` foreground, 0.5 opacity when disabled

---

## Phase 2: Stateful buttons (14 usages)

These use `ButtonState` (`.normal`, `.loading`, `.success`, `.successText`).

**Recommended approach**: handle state in the button's label closure. No new wrapper needed — keeps it explicit and composable.

```swift
Button {
    viewModel.action()
} label: {
    switch viewModel.buttonState {
    case .normal:
        Text("Save to Photos")
    case .loading:
        LoadingView(color: .textSecondary)
    case .success:
        Image.asset(.checkmark).renderingMode(.template)
    case .successText(let text):
        HStack(spacing: 10) {
            Image.asset(.checkmark).renderingMode(.template)
            Text(text)
        }
    }
}
.buttonStyle(.filled)
.disabled(!viewModel.buttonState.isNormal)
```

### Files to migrate

| File | Title | `state` | `disabled` |
|------|-------|:---:|:---:|
| AccessKeyScreen.swift | "Save Access Key to Photos" | Yes | No |
| AccessKeyBackupScreen.swift | "Save to Photos" | Yes | No |
| LoginScreen.swift | "Log In" | Yes | Yes |
| IntroScreen.swift | "Create a New Account" | Yes | No |
| EnterPhoneScreen.swift | "Next" | Yes | Yes |
| ConfirmPhoneScreen.swift | "Confirm" | Yes | Yes |
| EnterEmailScreen.swift | "Next" | Yes | Yes |
| ConfirmEmailScreen.swift | "Open Mail" | Yes | No |
| WithdrawSummaryScreen.swift | "Withdraw" | Yes | No |
| DepositScreen.swift | "Copy Address" | Yes | No |
| BuyAccountScreen.swift | "Purchase Your Account" | Yes | Yes |
| CurrencySellConfirmationScreen.swift | "Sell" | Yes | No |
| WithdrawAddressScreen.swift (x2) | "Paste"/"Next" | No | Yes |

---

## Phase 3: Dynamic style + Apple Pay

### `EnterAmountView.swift`
- Uses `mode.buttonStyle` which resolves to different `CodeButton.Style` values at runtime
- Migrate last once all style presets exist
- The mode enum should return a `ButtonStyle` value instead of `CodeButton.Style`

### `PresetAddCashScreen.swift` — `.filledApplePay`
- Just use `.filled` + custom label with Apple logo and "Pay" text
- No new style preset needed

---

## Phase 4: FlipcashUI cleanup

### SheetEnablePush.swift
- The only FlipcashUI file (outside CodeButton.swift itself) that uses `CodeButton`
- Migrate to `Button` + `FilledButtonStyle`

### Delete CodeButton.swift
- Once all Flipcash usages are gone and SheetEnablePush is migrated
- `CodeButton.Style` goes with it (nested type)

### Code/ and Flipchat/
- Out of scope — legacy/inactive modules, will be dealt with separately

---

## Summary

| Phase | Work | Files | Blocked by |
|-------|------|:-----:|:----------:|
| 1 | New style presets (`.filledSecondary`, `SubtleButtonStyle`) | 3 new/modified | — |
| 2 | Migrate stateful buttons | 14 screens | Phase 1 |
| 3 | Dynamic style + Apple Pay | 2 screens | Phase 1 |
| 4 | Delete CodeButton from Flipcash imports + SheetEnablePush | 2 files | Phase 2+3 |
