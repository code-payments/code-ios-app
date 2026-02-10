# Deeplink .onChange Race Condition

**Date:** 2026-02-10

## The Bug / Task

Token/currency deeplinks (`flipcash.com/token/{mint}`) sporadically failed when the app was backgrounded. The app would open to ScanScreen but not navigate to the currency info screen. Manually tapping the "Wallet" button worked fine.

## Root Cause

`AppDelegate.handleOpenURL` calls `assignHost()` (replaces the entire root view controller) then dispatches a `Task` that sets `session.pendingCurrencyInfoMint`. The new `ScanScreen` observed this property via `.onChange`, but `.onChange` only fires on transitions while the modifier is attached. If the value was set before the new view hierarchy started observing, the change was silently missed.

## What Went Wrong

### Attempt 1: Adding a parallel `.task` modifier
Proposed adding a `.task { if session.pendingCurrencyInfoMint != nil { isShowingBalance = true } }` alongside the existing `.onChange`. This was technically correct — `.task` catches the value on appear, `.onChange` catches runtime changes — but the user pointed out that someone reading the code would not understand why both modifiers exist doing nearly the same thing. Two parallel code paths for one concern is confusing.

### Attempt 2: Using `.onChange(initial: true)`
Replaced the existing `.onChange` with `.onChange(of:initial: true)`, an iOS 17+ parameter that tells SwiftUI to also fire the closure with the current value when the view first appears. One modifier, one intent, self-documenting.

## Lessons

1. **Before adding a second code path, check if the existing one can be parameterized.** `.onChange(initial: true)` was the obvious iOS 17 solution — it does exactly "check on appear AND on change" in one modifier.
2. **Code clarity matters as much as correctness.** Two modifiers doing the same thing works but confuses future readers. The best fix is the one that reads naturally.
3. **Know your API surface.** The `initial:` parameter on `.onChange` exists precisely for this use case. Reaching for `.task` + `.onChange` was reinventing what the framework already provides.
