# Quick Reference

## Key Files

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

Add Money (funding decoupled — Add Money only deposits USDF; buy & launch always spend USDF reserves):
- Flipcash/Core/Screens/Main/AddMoney/ (Select Method → Amount to Add → Adding Money screens)
- Flipcash/Core/Screens/Main/AddMoney/CoinbaseDepositOperation.swift (Coinbase + Apple Pay → USDC to the owner's ATA; sweep converts to USDF)
- Flipcash/Core/Screens/Main/AddMoney/PhantomDepositOperation.swift (Phantom-signed USDC→USDF swap to the USDF VM Deposit address)
- Flipcash/Core/Operations/UsdcSweepOperation.swift (sweepUntilConverted — converts deposited USDC → USDF)
- Flipcash/Core/Controllers/Onramp/OnrampHostModifier.swift (Apple Pay overlay plumbing, retained)

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

## Key Constants

```swift
// USDC
PublicKey.usdc // Main stablecoin mint
PublicKey.usdc.mintDecimals // 6

// Bonding Curve
BondingCurve.startPrice  // $0.01
BondingCurve.endPrice    // $1,000,000
BondingCurve.maxSupply   // 21,000,000 tokens
```

## Xcode MCP Server

**Prefer Xcode MCP tools over `xcodebuild` shell commands** when the Xcode MCP server is available. It provides direct integration with the open Xcode workspace for building, testing, reading/writing project files, rendering SwiftUI previews, and searching Apple documentation.

**Fall back to `./Scripts/build.sh` and `./Scripts/test.sh`** when the MCP server is not connected. See [Running the App & Tests](testing.md#running-the-app--tests) for usage. For edge cases the scripts don't cover (e.g., a one-off destination, `xcodebuild clean`), drop down to raw `xcodebuild`.

**Device builds.** XcodeBuildMCP ships device tools (`build_device`, `build_run_device`, `test_device`, `list_devices`, etc.) in its `device` workflow. They're available whenever `device` is in the `XCODEBUILDMCP_ENABLED_WORKFLOWS` list in your `.mcp.json` (that file is per-developer and gitignored — add `device` to the comma-separated list to turn them on). Use device tools the same way as the simulator ones. If they're not present (workflow not enabled, or the MCP server hasn't reloaded its config), silently fall back to `./Scripts/build.sh --device` — **never narrate which path you took.**

When you need to confirm a paired iPhone, use the `list_devices` MCP tool (or `xcrun devicectl list devices`). **Do not use `xcrun xctrace list devices`** — it mislabels paired iPhones as `Offline` and will lead you to falsely claim no device is connected.

If the user says "build on my device," take them at their word and just do it — don't push back claiming only simulators are available. Tests remain simulator-only.
