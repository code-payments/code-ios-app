# Give Flow Currency Selection Bug

**Date:** 2026-02-06

## The Bug

When a user starts with no balances, receives a balance, and opens the Give flow, the currency selector at the top shows nothing instead of having a currency pre-selected. Additionally, opening the Select Currency sheet showed no checkmark on any currency.

## Root Cause

`GiveViewModel.selectedBalance` was set once during `init()`. When balances didn't exist yet at init time, it stayed `nil`. The `isPresented` `didSet` checked for giveable balances but never refreshed `selectedBalance`.

## What Went Wrong

### Attempt 1: Static helper + refresh in `didSet`
Extracted balance resolution into a `static func resolveSelectedBalance()` and called it from both `init` and `isPresented` `didSet`. This duplicated logic that `Session.ensureValidTokenSelection()` already handles.

### Attempt 2: Removed `didSet`, added `prepare()` + `.onAppear`
Restructured the entire presentation flow by removing the `isPresented` `didSet` gating pattern and replacing it with a `prepare()` method called from `.onAppear` in the View. This caused:
- The sheet opened unconditionally (no gating)
- `prepare()` fired inside the sheet, found no giveable balances, dismissed the sheet
- Result: sheet flashes open then closes, error dialog appears, app freezes
- USDF-only users were broken because `prepare()` filtered out USDF

### Attempt 3: Trusting `ensureValidTokenSelection` too much
Added `refreshSelectedBalance()` back into the `didSet` but removed the fallback logic, assuming `ratesController.selectedTokenMint` would always point to a giveable (non-USDF) token. Wrong — `Session.ensureValidTokenSelection()` is a **global** selector that includes USDF. Its sort puts USDF first (`lhs.usdf > rhs.usdf`), so when balances arrive it often selects USDF. The Give flow filters out USDF, so `refreshSelectedBalance()` found no match and `selectedBalance` stayed `nil`.

### Attempt 4: Correct `refreshSelectedBalance` without fallback + no `ratesController` sync
Added back a fallback to `availableBalances.first` but forgot to sync the fallback selection to `ratesController.selectToken()`. This meant the toolbar showed the right currency (from local `selectedBalance`) but the Select Currency sheet's checkmark (driven by `ratesController.isSelectedToken()`) didn't match.

### Attempt 5: The correct fix
`refreshSelectedBalance()` now:
1. Tries to match `ratesController.selectedTokenMint` against giveable balances
2. If no match (e.g. selectedTokenMint is USDF or a stale mint), falls back to first giveable balance **and syncs to `ratesController`** so the checkmark in Select Currency sheet is correct

## Lessons

1. **Understand the existing architecture first.** `Session.ensureValidTokenSelection()` is a global selector — it doesn't know about the Give flow's USDF filter. The ViewModel must handle domain-specific filtering itself.
2. **Don't restructure working patterns for a narrow bug.** The `isPresented` `didSet` gating pattern is established in this codebase. Replacing it with `.onAppear` introduced a race condition.
3. **Test your mental model against all user scenarios.** The USDF-only case was missed because the focus was on the "no balance then balance" scenario.
4. **The smallest fix is usually the best fix.** One new method + one call site vs. restructuring the entire presentation flow.
5. **When setting local state, check if shared state needs to sync too.** `selectedBalance` (local) and `ratesController.selectedTokenMint` (shared) must agree, or different UI components will show inconsistent state (toolbar vs. selection sheet).
6. **"Trust the existing system" doesn't mean "assume it handles your specific case."** `ensureValidTokenSelection` is correct for its purpose, but the Give flow has additional constraints (no USDF) that the global selector doesn't know about.
