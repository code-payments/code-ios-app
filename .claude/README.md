# Flipcash iOS App - Codebase Guide

**Last Updated:** 2025-11-12

This document provides a comprehensive guide to the Flipcash iOS application codebase, including architecture, multi-currency system, and key concepts.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Repository Structure](#repository-structure)
3. [Flipcash App Architecture](#flipcash-app-architecture)
4. [Multi-Currency System](#multi-currency-system)
5. [Key Components](#key-components)
6. [Payment Flows](#payment-flows)
7. [Database Schema](#database-schema)
8. [Legacy Code](#legacy-code)
9. [Development Guidelines](#development-guidelines)

---

## Project Overview

### About Flipcash

**Flipcash** is a peer-to-peer payment application built on the Solana blockchain. It enables users to:

- **Send cash in-person** by scanning bills displayed on another device's screen
- **Send cash remotely** via cash links (gift card model using temporary accounts)
- **Create and use custom currencies** backed by bonding curves
- **Multi-currency support** with real-time exchange rates

**Status:** Production (App Store, live for ~1 year)

### Business Model

- Primary use case: P2P payments
- Two payment methods:
  1. **In-person scanning**: QR codes embedded in visual "bills"
  2. **Cash links**: Random account holds funds until recipient claims via deep link
- Custom currencies created by users (server-side, coming to mobile)
- **Note:** Pools/betting feature is being deprecated

---

## Repository Structure

```
code-ios-app/
├── Flipcash/              # Active app (FOCUS HERE)
│   ├── Core/
│   │   ├── AppDelegate.swift
│   │   ├── Container.swift          # DI container
│   │   ├── Controllers/             # Business logic
│   │   │   ├── Database/           # SQLite persistence
│   │   │   ├── HistoryController   # Transaction history
│   │   │   ├── RatesController     # Exchange rates
│   │   │   └── PoolController      # Pools (deprecated)
│   │   ├── Screens/                # All UI screens
│   │   │   ├── Main/
│   │   │   │   ├── Bill Editor/   # Current work: color customization
│   │   │   │   ├── ScanScreen     # Camera scanning
│   │   │   │   └── Operations/    # Send/receive flows
│   │   │   ├── Onboarding/
│   │   │   ├── Onramp/            # Coinbase integration
│   │   │   └── Settings/
│   │   └── Session/               # Session management
│       └── SessionAuthenticator.swift
│
├── FlipcashCore/          # Business logic package
│   ├── Models/
│   │   ├── Fiat.swift             # Quarks struct - currency amounts (smallest unit)
│   │   ├── ExchangedFiat.swift    # Multi-currency values (underlying + converted)
│   │   ├── BondingCurve.swift     # Pricing curves
│   │   └── MintMetadata.swift     # Token metadata
│   ├── Clients/
│   │   ├── Flip API/              # Backend API
│   │   └── Payments API/          # Blockchain APIs
│   └── Solana/                    # Solana integration
│
├── FlipcashUI/            # UI components library
│   ├── Views/
│   │   ├── Bill/                  # Bill visualization
│   │   ├── Buttons/
│   │   └── Controls/
│   └── Theme/                     # Design system
│
├── FlipcashAPI/           # gRPC proto definitions
├── FlipcashCoreAPI/       # Additional API layer
│
├── CodeServices/          # Shared Solana services
├── CodeCurves/            # Ed25519 cryptography
├── Shared/                # Localization & utilities
│
├── Code/                  # Legacy: Code Wallet (inactive)
└── Flipchat/             # Legacy: Chat app (inactive)
```

---

## Flipcash App Architecture

### Design Pattern

**MVVM + Container DI**

- **Container:** Dependency injection container manages all services
- **Session:** Main session object, created after authentication
- **SessionAuthenticator:** Handles login/logout lifecycle
- **ViewModels:** Per-screen, injected via `@EnvironmentObject`

### Tech Stack

- **Language:** Swift 6.1
- **UI:** SwiftUI (primary) + UIKit (AppDelegate, navigation)
- **Minimum iOS:** 17.0
- **Blockchain:** Solana (via CodeServices)
- **Database:** SQLite (via SQLite.swift)
- **Networking:** gRPC (grpc-swift)
- **Crypto:** Ed25519 (custom CodeCurves, swift-sodium)
- **Analytics:** Firebase, Mixpanel, Bugsnag

### Key Services

```swift
Container
├── Client              // Backend gRPC client
├── FlipClient          // Flipcash-specific APIs
├── AccountManager      // Keychain storage
└── SessionContainer (when logged in)
    ├── Session                 // Main session state
    ├── RatesController        // Exchange rates
    ├── HistoryController      // Transaction history
    ├── Database               // SQLite persistence
    ├── PoolController         // Pools (deprecated)
    └── PushController         // Push notifications
```

---

## Multi-Currency System

### Recent Architectural Changes (2025-11-12)

**Critical Naming Refactor:**

To better support multi-currency operations, two core types have been renamed:

1. **`Fiat` → `Quarks`**
   - **Why:** "Fiat" implied fiat currencies only, but the struct represents the smallest unit of *any* currency
   - **Impact:** All currency amount representations now use `Quarks`
   - **File:** Still located in `FlipcashCore/Sources/FlipcashCore/Models/Fiat.swift`

2. **`ExchangedFiat.usdc` → `ExchangedFiat.underlying`**
   - **Why:** The field was hardcoded to USDC during single-currency era
   - **Impact:** Now properly represents that the underlying value can be any token (USDC, Farmer Coin, etc.)
   - **Usage:**
     - `underlying`: Blockchain asset being held (can be any mint)
     - `converted`: Display currency for user (USD, JPY, CAD, etc.)

**Migration Context:**

These changes reflect the evolution from USDC-only to full multi-currency support. The `converted` field has always been the "visual" value shown to users, while `underlying` (formerly `usdc`) represents the actual on-chain asset value.

### Core Concepts

Flipcash supports multiple currencies, each represented by a Solana token mint:

1. **USDC** - Base currency, "core mint"
2. **Custom Currencies** - User-created tokens with bonding curves

### Currency Representation

#### 1. Quarks

Represents currency amounts using **quarks** (smallest unit):

```swift
struct Quarks {
    let quarks: UInt64       // Raw amount (e.g., 1,500,000 quarks)
    let currencyCode: CurrencyCode  // .usd, .eur, .cad, etc.
    let decimals: Int        // Decimal places (e.g., 6 for USDC)
}

// Example: $1.50 USD = 1,500,000 quarks (6 decimals)
let amount = Quarks(quarks: 1_500_000, currencyCode: .usd, decimals: 6)
// amount.decimalValue == 1.50
```

**Naming Note:**
- Previously called `Fiat` (legacy from USDC-only era)
- Renamed to `Quarks` to better reflect multi-currency support
- Represents smallest unit of **any** currency (not just fiat)

**Key Operations:**
- `adding()`, `subtracting()` - Arithmetic (requires matching currency/decimals)
- `scaled(to:)` - Scale quarks to different decimal precision
- `calculateFee(bps:)` - Calculate fee in basis points

#### 2. ExchangedFiat

Wraps both underlying currency value and converted display value with exchange rate:

```swift
struct ExchangedFiat {
    let underlying: Quarks   // Underlying currency (USDC or custom token)
    let converted: Quarks    // Converted to user's display currency
    let rate: Rate           // Exchange rate
    let mint: PublicKey      // Token mint address
}

// Example: $5.00 CAD displayed (rate: 1.40 CAD/USD)
// underlying: 3.57 USD worth of USDC quarks
// converted: 5.00 CAD (visual/display currency)
// rate: Rate(fx: 1.40, currency: .cad)
// mint: PublicKey.usdc
```

**Field Explanation:**
- **`underlying`**: The actual currency held (USDC, Farmer Coin, or any custom token)
  - Represents the blockchain-level asset
  - Can be any token mint (not just USDC)
- **`converted`**: The display currency shown to user (USD, CAD, JPY, EUR, etc.)
  - Always in the user's preferred fiat currency
  - Used for UI display and tolerance calculations

**Naming History:**
- Previously: `usdc: Fiat` (hardcoded for USDC-only era)
- Now: `underlying: Quarks` (supports any currency/token)

**Creation Methods:**
- `init(underlying:rate:mint:)` - From underlying token amount
- `init(converted:rate:mint:)` - From display currency amount
- `computeFromQuarks()` - From raw quarks with bonding curve
- `computeFromEntered()` - From user-entered amount

#### 3. BondingCurve

Exponential pricing curve for custom currencies:

```swift
struct BondingCurve {
    let a: BigDecimal  // Curve parameter (default: 11400.23...)
    let b: BigDecimal  // Curve parameter (default: 0.000000877...)
    let c: BigDecimal  // Curve parameter (default: 0.000000877...)
}
```

**Price Formula:**
```
P(S) = a * b * e^(c*S)
```

Where:
- `S` = Current supply (in tokens)
- `P(S)` = Spot price at supply S

**Key Methods:**
- `spotPrice(supply:)` - Get current price
- `costToBuy(quarks:supply:)` - Calculate cost to buy tokens
- `valueFromSelling(quarks:tvl:)` - Calculate value from selling tokens
- `tokensBought(withUSDC:tvl:)` - Calculate tokens received for USDC
- `buy()` / `sell()` - With fee calculations

**Parameters:**
- Start price: $0.01
- End price: $1,000,000
- Max supply: 21,000,000 tokens
- Sell fee: 1% (100 bps)

### Database Models

#### StoredBalance

```swift
struct StoredBalance {
    let quarks: UInt64              // Raw balance
    let symbol: String              // "USDC", "FLIP", etc.
    let name: String                // Display name
    let supplyFromBonding: UInt64?  // Circulating supply
    let coreMintLocked: UInt64?     // TVL in USDC
    let sellFeeBps: Int?            // Sell fee (100 = 1%)
    let mint: PublicKey             // Token mint address
    let vmAuthority: PublicKey?     // VM authority
    let usdcValue: Quarks           // Computed USDC value
}
```

**USDC Value Calculation:**
- **USDC balances:** `usdcValue = quarks` (1:1)
- **Custom currencies:** Uses bonding curve:
  ```swift
  let estimation = bondingCurve.sell(
      quarks: quarks,
      feeBps: sellFeeBps,
      tvl: coreMintLocked
  )
  usdcValue = estimation.netUSDC
  ```

#### StoredMintMetadata

```swift
struct StoredMintMetadata {
    let mint: PublicKey
    let name: String
    let symbol: String
    let decimals: Int
    let imageURL: URL?

    // VM metadata (Virtual Machine for timelocks)
    let vmAddress: PublicKey?
    let vmAuthority: PublicKey?
    let lockDuration: Int?

    // Launchpad metadata (bonding curve info)
    let currencyConfig: PublicKey?
    let liquidityPool: PublicKey?
    let supplyFromBonding: UInt64?
    let coreMintLocked: UInt64?
    let sellFeeBps: Int?
}
```

### Exchange Rate System

#### Rate

```swift
struct Rate {
    let fx: Decimal        // Exchange rate (e.g., 1.40 for CAD)
    let currency: CurrencyCode
}
```

#### RatesController

Manages exchange rates:

```swift
class RatesController {
    func rateForBalanceCurrency() -> Rate  // Display currency
    func rateForEntryCurrency() -> Rate    // Input currency
    func rate(for: CurrencyCode) -> Rate?  // Specific currency
}
```

Rates are:
- Fetched from backend
- Cached in SQLite
- Refreshed periodically

---

## Key Components

### Session

**Location:** `Flipcash/Core/Session/Session.swift`

Main session object managing app state:

```swift
class Session: ObservableObject {
    // State
    @Published var billState: BillState
    @Published var presentationState: PresentationState
    @Published var toast: Toast?
    @Published var dialogItem: DialogItem?

    // Data
    let keyAccount: KeyAccount
    let owner: AccountCluster
    let userID: UserID

    // Computed
    var balances: [StoredBalance]
    var totalBalance: ExchangedFiat

    // Methods
    func receiveCash(payload:)
    func showCashBill(description:)
    func dismissCashBill(style:)
    func withdraw(exchangedFiat:fee:to:)
    func fetchBalance()
    func updatePostTransaction()
}
```

### SessionAuthenticator

**Location:** `Flipcash/Core/Session/SessionAuthenticator.swift`

Handles authentication lifecycle:

```swift
class SessionAuthenticator: ObservableObject {
    @Published var state: AuthenticationState

    enum AuthenticationState {
        case loggedOut
        case migrating
        case pending
        case loggedIn(SessionContainer)
    }

    func initialize(using:isRegistration:) async throws
    func completeLogin(with:)
    func logout()
    func switchAccount(to:)
}
```

### Database

**Location:** `Flipcash/Core/Controllers/Database/`

SQLite database with versioned schema:

**Tables:**
- `balance` - User balances per mint
- `mint` - Mint metadata
- `rate` - Exchange rates
- `activity` - Transaction history
- `cashLinkMetadata` - Cash link details
- `pool` / `bet` - Pools (deprecated)

**Current Version:** 6 migrations

**Key Operations:**
```swift
func insertBalance(quarks:mint:date:)
func getBalances() -> [StoredBalance]
func insert(mints:date:)
func getMintMetadata(mint:) -> StoredMintMetadata?
func getVMAuthority(mint:) -> PublicKey?
```

---

## Payment Flows

### 1. In-Person Payment (Scan Bill)

**Sender:**
```swift
// 1. User enters amount
let exchangedFiat = ExchangedFiat.computeFromEntered(...)

// 2. Check funds
let (hasFunds, _) = session.hasSufficientFunds(for: exchangedFiat)

// 3. Show bill
session.showCashBill(.init(
    kind: .cash,
    exchangedFiat: exchangedFiat,
    received: false
))

// 4. SendCashOperation starts stream
// 5. Receiver scans -> funds transfer
// 6. Bill dismissed with pop animation
```

**Receiver:**
```swift
// 1. Camera detects QR code
let payload = CashCode.Payload(...)

// 2. Session receives cash
session.receiveCash(payload) { result in
    switch result {
    case .success:
        // Show received bill
        session.showCashBill(.init(
            kind: .cash,
            exchangedFiat: metadata.exchangedFiat,
            received: true
        ))
    }
}

// 3. ScanCashOperation handles transfer
// 4. Update balance, show toast
```

### 2. Cash Links (Remote Payment)

**Sender:**
```swift
// 1. Show bill
session.showCashBill(...)

// 2. User taps "Send as a Link"
let giftCard = try await session.createCashLink(
    payload: payload,
    exchangedFiat: exchangedFiat
)

// 3. Share sheet presented
session.showCashLinkShareSheet(giftCard:exchangedFiat:)

// 4. User confirms send
// Funds locked in giftCard account

// 5. Auto-return after 7 days if unclaimed
```

**Receiver:**
```swift
// 1. Deep link opens app
// Format: flipcash://cash?data=<mnemonic>

// 2. Fetch gift card info
let accountInfo = try await client.fetchAccountInfo(
    type: .giftCard,
    owner: giftCardKeyPair
)

// 3. Claim funds
try await client.receiveCashLink(
    underlying: exchangedFiat.underlying,
    ownerCluster: owner,
    giftCard: giftCard
)

// 4. Show received bill
```

### 3. Withdrawals (to External Wallet)

```swift
try await session.withdraw(
    exchangedFiat: exchangedFiat,
    fee: fee,
    to: destinationMetadata
)

// Backend creates withdrawal intent
// Funds sent to destination address
```

---

## Database Schema

### Balance Table

```sql
CREATE TABLE balance (
    mint       BLOB PRIMARY KEY,  -- PublicKey
    quarks     INTEGER,           -- UInt64
    updatedAt  REAL               -- Date
);
```

### Mint Table

```sql
CREATE TABLE mint (
    mint              BLOB PRIMARY KEY,
    name              TEXT,
    symbol            TEXT,
    decimals          INTEGER,
    bio               TEXT,
    imageURL          TEXT,

    -- VM Metadata
    vmAddress         BLOB,
    vmAuthority       BLOB,
    lockDuration      INTEGER,

    -- Launchpad Metadata (Bonding Curve)
    currencyConfig    BLOB,
    liquidityPool     BLOB,
    seed              BLOB,
    authority         BLOB,
    mintVault         BLOB,
    coreMintVault     BLOB,
    coreMintFees      BLOB,
    supplyFromBonding INTEGER,
    coreMintLocked    INTEGER,
    sellFeeBps        INTEGER,

    updatedAt         REAL
);
```

### Rate Table

```sql
CREATE TABLE rate (
    currency  TEXT PRIMARY KEY,  -- CurrencyCode
    fx        REAL,              -- Exchange rate
    updatedAt REAL               -- Date
);
```

---

## Legacy Code

### What to Avoid

The repository contains two legacy apps:

1. **Code Wallet** (`/Code`) - Original Kin wallet
2. **Flipchat** (`/Flipchat`) - Chat-focused app

**Important:**
- These apps are **not under active development**
- Most concepts carry over to Flipcash (intents, rendezvous, keys)
- **REMOVED:** Trays/Organizer privacy system (denomination-based obfuscation)

### Shared Code

Some packages are shared:

- **CodeServices** - Solana blockchain services (ACTIVELY USED)
- **CodeCurves** - Ed25519 crypto (ACTIVELY USED)
- **CodeAPI** - Legacy gRPC definitions (AVOID, use FlipcashAPI)
- **CodeUI** - Legacy UI components (AVOID, use FlipcashUI)

---

## Development Guidelines

### When Working on Multi-Currency Features

1. **Always consider both USDC and custom currencies**
   - USDC: Direct 1:1 quarks <-> value
   - Custom: Use bonding curve for valuation

2. **Use ExchangedFiat for all UI displays**
   - Contains both USDC and converted values
   - Automatically handles exchange rates

3. **Check mint metadata before operations**
   - VM authority required for transactions
   - Bonding curve params needed for pricing

4. **Account cluster management**
   - Each mint requires separate account cluster
   - Use `owner.use(mint:timeAuthority:)` to switch

### Testing Multi-Currency

```swift
// Test bonding curve
let curve = BondingCurve()
let estimation = curve.sell(
    quarks: 1_000_000_000, // 1 token (10 decimals)
    feeBps: 100,           // 1% fee
    tvl: 100_000_000       // $100 USDC locked
)
print(estimation.netUSDC) // USDC received

// Test Quarks alignment
let quarks1 = Quarks(quarks: 100, currencyCode: .usd, decimals: 6)
let quarks2 = Quarks(quarks: 100, currencyCode: .usd, decimals: 2)
let result = try quarks1.subtractingScaled(quarks2)
// Automatically scales to common decimals
```

### Common Patterns

**Fetching Balance:**
```swift
let balances = session.balances
let totalBalance = session.totalBalance

// Or for specific mint:
if let balance = session.balance(for: .usdc) {
    print(balance.usdcValue)
}
```

**Converting Amounts:**
```swift
let entryRate = ratesController.rateForEntryCurrency()
let exchanged = balance.computeExchangedValue(with: entryRate)
// exchanged.underlying = underlying currency value (USDC or custom token)
// exchanged.converted = value in user's display currency
```

**Creating ExchangedFiat:**
```swift
// From user entry
let exchanged = ExchangedFiat.computeFromEntered(
    amount: 5.00,          // User entered $5
    rate: entryRate,       // Current rate
    mint: selectedMint,    // Token mint
    supplyFromBonding: supply
)

// From existing quarks
let exchanged = ExchangedFiat.computeFromQuarks(
    quarks: quarks,
    mint: mint,
    rate: rate,
    tvl: coreMintLocked
)
```

---

## Current Development Focus

### Bill Editor (Active Work)

**Location:** `Flipcash/Core/Screens/Main/Bill Editor/`

**Purpose:** Allow users to customize bill colors for custom currencies

**Features:**
- 10 solid color presets
- 10 gradient presets (1-3 colors)
- Custom HSB color picker
- Live preview on bill
- Haptic feedback
- Smooth animations

**Files:**
- `BillEditor.swift` - Main editor screen
- `ColorEditorControl.swift` - HSB picker (594 lines)
- Custom Canvas rendering for performance

### Recent Work

1. **Multi-currency improvements**
   - Bonding curve integration
   - ExchangedFiat alignment
   - Database schema updates
   - Architectural refactor: `Fiat` → `Quarks`, `usdc` → `underlying`

2. **Currency-aware tolerance logic (2025-11-12)**
   - Fixed JPY "0 Yen short" bug with small balances
   - Tolerance now calculated per currency's decimal places:
     - USD (2 decimals): 0.005 (half a penny)
     - JPY (0 decimals): 0.5 (half a yen)
     - BHD (3 decimals): 0.0005 (half a fils)
   - Formula: `tolerance = (10^-decimals) / 2`
   - Location: `Session.hasSufficientFunds()` (Session.swift:326-351)
   - Test coverage: 9 comprehensive tests in SessionTests.swift

3. **Fiat validation**
   - Decimal scaling
   - Cross-currency arithmetic
   - Error handling

4. **Transaction tracking**
   - Grab time recording
   - Activity history
   - Analytics events

---

## Important Notes

### Pools/Betting (Deprecated)

The pools/betting feature is being shut down:
- No new work planned
- Code exists in:
  - `Flipcash/Core/Screens/Pools/`
  - `PoolController.swift`
  - Database tables: `pool`, `bet`
- Safe to ignore when working on other features

### Custom Currencies

Custom currencies are coming to mobile:
- Currently hardcoded on server
- Not visible in codebase yet
- Bill editor prepares for this feature

### Backend Integration

Separate backend repository exists:
- gRPC APIs defined in FlipcashAPI
- Backend handles:
  - User accounts
  - Transaction intents
  - Exchange rates
  - Mint metadata
  - Currency creation

### gRPC Proto Updates (FlipcashGen)

**Overview:**

The Flipcash app communicates with the backend via gRPC. Protocol definitions (`.proto` files) are managed in a separate repository and code generation is handled by the **FlipcashGen** Xcode target.

**Workflow:**

1. **Pull Latest Protos:**
   - FlipcashGen target fetches the latest `.proto` files from the proto repository
   - Run the generation script to create Swift files from protos

2. **Generated Files:**
   - Location: Auto-generated by FlipcashGen
   - **Never modify directly** - changes will be overwritten on next generation
   - These files define the gRPC service interfaces and message types

3. **Update Services:**
   - Services use the generated files (e.g., `AccountService`, `TransactionService`)
   - When protos update, services must be updated to match new APIs

**Common Update Scenarios:**

**A. Model Changes:**
- New fields added to existing messages
- Fields removed from messages
- New error types introduced
- Enum cases added/removed

**Actions Required:**
- Update model mapping code in services
- Handle new/removed fields appropriately
- Update error handling for new error types
- Ensure backward compatibility where needed

**B. RPC Changes:**
- New RPCs added to services
- Existing RPCs removed or deprecated
- RPC signatures changed (request/response types)

**Actions Required:**
- Add/remove corresponding Swift methods in service classes
- **IMPORTANT:** Update Client+ extension files with async/await wrappers
- Update call sites using changed RPCs
- Handle new request/response structures

**Client Extension Pattern:**
When adding a new RPC method to a Service (e.g., `AccountService`), you MUST also add a corresponding async/await wrapper in the Client extension file:

```swift
// 1. Add method to Service (e.g., AccountService.swift)
func fetchUserFlags(userID: UserID, owner: KeyPair, completion: @Sendable @escaping (Result<UserFlags, ErrorFetchUserFlags>) -> Void) {
    // Implementation with completion handler
}

// 2. Add async wrapper to Client extension (e.g., FlipClient+Account.swift)
extension FlipClient {
    public func fetchUserFlags(userID: UserID, owner: KeyPair) async throws -> UserFlags {
        try await withCheckedThrowingContinuation { c in
            accountService.fetchUserFlags(userID: userID, owner: owner) { c.resume(with: $0) }
        }
    }
}
```

**Service to Client+ Mapping:**
```
Service File                              → Client Extension File
----------------------------------------------------------------------
AccountService.swift                      → FlipClient+Account.swift
TransactionService.swift                  → FlipClient+Transaction.swift
BadgeService.swift                        → FlipClient+Badge.swift
CurrencyService.swift                     → FlipClient+Currency.swift
MessagingService.swift                    → FlipClient+Messaging.swift
```

This pattern ensures:
- Services use completion handlers for internal implementation
- Public API uses modern async/await
- Consistent interface across all client methods

**C. New Models:**
- Sometimes new proto messages require new Swift models
- These should be created in appropriate model directories
- Should follow existing naming and structure patterns

**Discussion Points:**
- When new models are needed, discuss:
  - Where should the model live? (FlipcashCore/Models, Database/Models, etc.)
  - Should it be `Codable`? `Equatable`?
  - Does it need database persistence?
  - How does it integrate with existing models?

**Example Service Files:**
```
FlipcashCore/Sources/FlipcashCore/Clients/
├── AccountService.swift      # Account-related RPCs
├── TransactionService.swift  # Transaction RPCs
└── ...                       # Other services
```

**Key Principle:**
- Generated files = read-only
- Service files = where we implement integration with generated code
- Always update both models AND services when protos change

---

## Quick Reference

### Key File Locations

```
Multi-Currency System:
- FlipcashCore/Sources/FlipcashCore/Models/Fiat.swift (contains Quarks struct)
- FlipcashCore/Sources/FlipcashCore/Models/ExchangedFiat.swift
- FlipcashCore/Sources/FlipcashCore/Models/BondingCurve.swift
- FlipcashCore/Sources/FlipcashCore/Models/MintMetadata.swift

Session & Auth:
- Flipcash/Core/Session/Session.swift (1133 lines)
- Flipcash/Core/Session/SessionAuthenticator.swift (466 lines)

Database:
- Flipcash/Core/Controllers/Database/Schema.swift
- Flipcash/Core/Controllers/Database/Models/StoredBalance.swift
- Flipcash/Core/Controllers/Database/Models/StoredMintMetadata.swift

Current Work:
- Flipcash/Core/Screens/Main/Bill Editor/BillEditor.swift
- Flipcash/Core/Screens/Main/Bill Editor/ColorEditorControl.swift
```

### Key Constants

```swift
// Bonding Curve
BondingCurve.startPrice = 0.01      // $0.01
BondingCurve.endPrice = 1_000_000   // $1M
BondingCurve.maxSupply = 21_000_000 // 21M tokens

// USDC
PublicKey.usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
PublicKey.usdcAuthority = "noaUtmcNjMFfE2Udd9dky67x5JNBAYfUGpq4cakZxzp"
PublicKey.usdc.mintDecimals = 6

// Database
SQLiteVersion = 6 (migrations)

// Timeouts
Poller interval = 10 seconds
Toast duration = 3 seconds
Cash link expiry = 7 days
```

---

## Coding Principles & Patterns

### Exhaustive Switch Statements

**Principle:** Always prefer `switch` statements over `if case` when working with enums for compile-time safety.

**Why:**
- ✅ **Compiler-enforced exhaustiveness:** Adding a new enum case will cause a compilation error, not a runtime crash
- ✅ **No `default` cases needed:** Forces explicit handling of all cases
- ✅ **Refactoring safety:** Changes to enums are caught at compile-time across the entire codebase
- ✅ **Self-documenting:** All possible states are visible in one place

**Example:**

```swift
// ❌ BAD: Using if case (silent failure if enum changes)
guard case .sufficient(let amountToSend) = result else {
    showInsufficientBalanceError()
    return
}
// If a new enum case is added, this code still compiles but may fail at runtime

// ✅ GOOD: Using switch (compiler error if enum changes)
switch result {
case .sufficient(let amountToSend):
    // Handle sufficient funds
    session.showCashBill(...)

case .insufficient(let shortfall):
    // Handle insufficient funds
    if let shortfall {
        showYoureShortError(amount: shortfall)
    } else {
        showInsufficientBalanceError()
    }
}
// If a new enum case is added, compiler forces us to handle it
```

**Real Example in Codebase:**

See:
- `GiveViewModel.giveAction()` (Flipcash/Core/Screens/Main/GiveViewModel.swift:98)
- `WithdrawViewModel.amountEnteredAction()` (Flipcash/Core/Screens/Settings/WithdrawViewModel.swift:274)
- `WithdrawViewModel.canCompleteWithdrawal` (Flipcash/Core/Screens/Settings/WithdrawViewModel.swift:138)

**When to Use:**

- ✅ **Always** when handling enum values that represent distinct states
- ✅ When exhaustive checking is important for correctness
- ✅ When enum may evolve over time

**When if case is Acceptable:**

- Only when you genuinely don't care about other cases and failure is acceptable
- When working with optional values (`.some`/`.none`)

---

**End of Guide**

For questions or clarifications, refer to inline code documentation or ask the development team.
