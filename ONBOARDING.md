# Flipcash iOS Developer Onboarding Guide

This comprehensive guide is designed to help new developers understand the Flipcash iOS codebase. It covers architecture, patterns, and implementation details across all major systems.

---

## Table of Contents

1. [Project Architecture & Structure](#1-project-architecture--structure)
2. [Authentication & Session Management](#2-authentication--session-management)
3. [Multi-Currency System](#3-multi-currency-system)
4. [CodeScanner (2D Code System)](#4-codescanner-2d-code-system)
5. [Database & Persistence](#5-database--persistence)
6. [gRPC & Networking](#6-grpc--networking)
7. [UI Architecture](#7-ui-architecture)
8. [Intent & Action System](#8-intent--action-system)
9. [Controllers & Business Logic](#9-controllers--business-logic)
10. [Cryptography & Key Management](#10-cryptography--key-management)
11. [Transaction System](#11-transaction-system)
12. [Testing Patterns](#12-testing-patterns)

---

## 1. Project Architecture & Structure

### Package/Module Overview

The project uses a **hybrid architecture**: Swift Package Manager (SPM) for business logic combined with an Xcode project wrapper for the iOS app.

```
code-ios-app/
├── Flipcash/                 # Main iOS app (Xcode project)
├── FlipcashCore/             # Business logic (SPM)
├── FlipcashUI/               # UI components (SPM)
├── FlipcashAPI/              # gRPC proto definitions - Flipcash API (SPM)
├── FlipcashCoreAPI/          # gRPC proto definitions - Payments API (SPM)
├── CodeCurves/               # Ed25519 cryptography (SPM)
├── CodeScanner/              # C++ circular code scanning
├── CodeServices/             # Legacy shared services (DO NOT import in Flipcash)
└── Code.xcodeproj/           # Xcode project file
```

### Dependency Graph

```
                    Flipcash App
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
   FlipcashCore    FlipcashUI       CodeScanner
         │               │
         ▼               │
   ┌─────┴─────┐         │
   │           │         ▼
FlipcashAPI  FlipcashCoreAPI
   │           │
   └─────┬─────┘
         │
         ▼
    CodeCurves
```

**Critical Rule:** Flipcash NEVER imports CodeServices directly. Use `import FlipcashCore` instead.

### Key Directories in Flipcash App

```
Flipcash/Core/
├── AppDelegate.swift         # App lifecycle, window setup
├── Container.swift           # Root DI container
├── ContainerScreen.swift     # Root navigation (auth state routing)
├── Session/                  # Auth, session management
│   ├── Session.swift         # Main state object
│   ├── SessionAuthenticator.swift
│   └── AccountManager.swift  # Keychain management
├── Controllers/              # Business logic
│   ├── Database/             # SQLite persistence
│   ├── HistoryController.swift
│   ├── RatesController.swift
│   └── PushController.swift
└── Screens/                  # SwiftUI screens
    ├── Main/                 # Authenticated screens
    ├── Onboarding/           # Login/registration
    ├── Onramp/               # Add cash flow
    └── Settings/             # User settings
```

### Technology Stack

| Technology | Version | Purpose |
|------------|---------|---------|
| Swift | 6.1 | Primary language |
| iOS Minimum | 17.0 | Deployment target |
| SwiftUI | Primary | UI framework |
| SQLite.swift | - | Database |
| grpc-swift | 1.22.0+ | Networking |
| CodeCurves | - | Ed25519 cryptography |
| OpenCV | 4.10.0 | Code scanning |

---

## 2. Authentication & Session Management

### State Machine

```
AuthenticationState:
├── .loggedOut          → IntroScreen (mnemonic entry)
├── .migrating          → LoadingView (app startup)
├── .pending            → (transitional state)
└── .loggedIn(SessionContainer) → ScanScreen (main app)
```

### Login Flow

```
User enters 12-word mnemonic
        ↓
Derive keypair: KeyPair(mnemonic, path: .primary())
        ↓
Create KeyAccount (mnemonic + derivedKey)
        ↓
Create AccountCluster (owner + timelock accounts)
        ↓
Server registration: flipClient.register(owner:)
        ↓
Store in Keychain via @SecureCodable
        ↓
Create SessionContainer:
├── Session (main state)
├── Database (per-user SQLite)
├── HistoryController
├── RatesController
├── PushController
└── WalletConnection
        ↓
state = .loggedIn(SessionContainer)
```

### Key Classes

| Class | Location | Purpose |
|-------|----------|---------|
| `SessionAuthenticator` | `Session/SessionAuthenticator.swift` | Auth state machine |
| `Session` | `Session/Session.swift` | Main app state (ObservableObject) |
| `AccountManager` | `Session/AccountManager.swift` | Keychain persistence |
| `KeyAccount` | `FlipcashCore/Solana/Keys/KeyAccount.swift` | Mnemonic + derived keys |

### SessionContainer (Post-Login Dependencies)

```swift
struct SessionContainer {
    let session: Session
    let database: Database
    let walletConnection: WalletConnection
    let ratesController: RatesController
    let historyController: HistoryController
    let pushController: PushController
    let poolController: PoolController
    let poolViewModel: PoolViewModel
    let onrampViewModel: OnrampViewModel
}
```

---

## 3. Multi-Currency System

### Core Concepts

**Quarks** - Smallest unit of currency (like cents for dollars)
- Stored as `UInt64` to avoid floating-point precision issues
- USDC uses 6 decimals: 1 USDC = 1,000,000 quarks
- Custom tokens use 10 decimals: 1 token = 10,000,000,000 quarks

**ExchangedFiat** - Amount with exchange rate conversion
```swift
struct ExchangedFiat {
    let underlying: Quarks   // Always in USD
    let converted: Quarks    // Display currency (CAD, EUR, etc.)
    let rate: Rate           // FX rate used
    let mint: PublicKey      // Which token
}
```

**Rate** - Foreign exchange rate
```swift
struct Rate {
    var fx: Decimal          // e.g., 1.4 for CAD
    var currency: CurrencyCode
}
```

### Bonding Curve

The **DiscreteBondingCurve** calculates token pricing based on Total Value Locked (TVL):
- 100-token steps with constant price per step
- Precomputed lookup tables for efficiency
- Matches Solana program exactly (no floating-point drift)

```swift
// Buy tokens with USD
let estimation = curve.buy(usdcQuarks: amount, feeBps: 100, tvl: tvl)

// Sell tokens for USD
let estimation = curve.sell(tokenQuarks: amount, feeBps: 100, tvl: tvl)
```

### Key Files

| File | Purpose |
|------|---------|
| `Models/Quarks.swift` | Atomic currency unit |
| `Models/ExchangedFiat.swift` | Multi-currency wrapper |
| `Models/Rate.swift` | Exchange rate |
| `Models/DiscreteBondingCurve.swift` | Token pricing |
| `Controllers/RatesController.swift` | Rate management |

### Currency Flow Example

```
User in Canada enters $10 CAD:
1. Exchange rate: 1 CAD = 0.714 USD
2. Convert: $10 / 1.4 = $7.14 USD
3. Bonding curve: $7.14 USD = 714 tokens
4. Store as ExchangedFiat:
   - underlying: $7.14 USD
   - converted: $10.00 CAD
   - rate: 1.4 CAD/USD
```

---

## 4. CodeScanner (2D Code System)

### Architecture

CodeScanner is a C++ library for scanning/encoding circular "Kik Codes":

```
Flipcash Swift Code
        ↓
KikCodes (Objective-C API)
        ↓
C++ Scanner (OpenCV 4.10.0)
        ↓
Reed-Solomon Error Correction
```

### Public API

```objc
@interface KikCodes : NSObject
+ (NSData *)encode:(NSData *)data;   // 20-byte → 35-byte
+ (NSData *)decode:(NSData *)data;   // 35-byte → 20-byte
+ (nullable NSData *)scan:(NSData *)data
                    width:(NSInteger)width
                   height:(NSInteger)height
                  quality:(KikCodesScanQuality)quality;
@end
```

### Payload Structure (20 bytes)

```
Byte 0:    Type (1 byte) - Kind enum
Byte 1:    Currency Code (1 byte)
Bytes 2-9: Fiat Amount (8 bytes) - UInt64 quarks
Bytes 10-19: Nonce (10 bytes) - random
```

### Swift Integration

```swift
// Scanning
if let data = KikCodes.scan(yPlaneData, width: width, height: height, quality: .best) {
    let payload = KikCodes.decode(data)
    let cashCode = try CashCode.Payload(data: payload)
}

// Encoding
let encoded = KikCodes.encode(payloadData)
```

### Key Files

| File | Purpose |
|------|---------|
| `CodeScanner/Code.h` | Objective-C public interface |
| `CodeScanner/src/scanner.cpp` | OpenCV scanning (~1000 lines) |
| `CodeScanner/src/kikcode_encoding.cpp` | Encoding/decoding logic |
| `Flipcash/Bill/CodeExtractor.swift` | Swift camera integration |
| `Flipcash/Bill/CashCode.Payload.swift` | Payload model |

---

## 5. Database & Persistence

### SQLite Architecture

```swift
class Database {
    let reader: Connection  // Read-only
    let writer: Connection  // Read-write, WAL mode
}
```

**Configuration:**
- WAL (Write-Ahead Logging) for concurrency
- 10,000 page cache (~20-40MB)
- Foreign keys enabled
- 2-second busy timeout
- Per-user database: `flipcash-{publicKey}.sqlite`

### Tables

| Table | Primary Key | Purpose |
|-------|-------------|---------|
| `balance` | mint | User's token holdings |
| `mint` | mint | Token metadata |
| `rate` | currency | Exchange rates |
| `activity` | id | Transaction history |
| `cashLinkMetadata` | id | Gift card details |
| `pool` | id | Betting pools (deprecated) |
| `bet` | id | Individual bets (deprecated) |

### Reactive Pattern

```swift
// Updateable wrapper auto-refreshes on database changes
class Updateable<T>: ObservableObject {
    @Published var value: T

    init(_ valueBlock: @escaping () -> T) {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDatabaseDidChange),
            name: .databaseDidChange, object: nil
        )
    }
}

// Usage in Session
private lazy var updateableBalances = Updateable {
    (try? database.getBalances()) ?? []
}
```

### Query Pattern

```swift
// Write (uses writer connection)
try database.transaction {
    try $0.insertBalance(quarks: amount, mint: mint, date: .now)
}

// Read (uses reader connection)
let balances = try database.getBalances()
```

---

## 6. gRPC & Networking

### Dual Client Architecture

1. **Client** (Payments API) - Solana blockchain operations
   - Host: `ocp.api.flipcash-infra.net:443`
   - Services: Account, Transaction, Currency, Messaging

2. **FlipClient** (Flipcash API) - Backend services
   - Host: `fc.api.flipcash-infra.net:443`
   - Services: Account, Activity, Profile, Push, IAP, Pool

### Client Pattern

```swift
@MainActor
class FlipClient: ObservableObject {
    internal let accountService: AccountService
    internal let activityService: ActivityService
    // ... more services

    // Public methods exposed via extensions
    public func login(owner: KeyPair) async throws -> UserID {
        try await withCheckedThrowingContinuation { c in
            accountService.login(owner: owner) { c.resume(with: $0) }
        }
    }
}
```

### Request Signing

All API calls include cryptographic authentication:

```swift
let request = Flipcash_Account_V1_LoginRequest.with {
    $0.timestamp = .init(date: .now)
    $0.auth = owner.authFor(message: $0)  // Ed25519 signature
}
```

### Error Handling

Each service defines domain-specific errors:

```swift
enum ErrorSendEmailCode: Int, Error {
    case ok
    case denied
    case rateLimited
    case invalidEmailAddress
    case unknown = -1
}
```

---

## 7. UI Architecture

### Screen Organization

```
Flipcash/Core/Screens/
├── Main/               # Authenticated screens
│   ├── ScanScreen.swift
│   ├── GiveScreen.swift
│   ├── BalanceScreen.swift
│   └── Operations/     # Async operations
├── Onboarding/         # Login flow
├── Onramp/             # Add cash flow
├── Settings/           # User settings
└── Pools/              # Betting (deprecated)
```

### Navigation Patterns

**1. State-Driven (Root)**
```swift
// ContainerScreen.swift
switch sessionAuthenticator.state {
case .loggedOut: IntroScreen()
case .migrating: LoadingView()
case .loggedIn(let container): ScanScreen()
}
```

**2. NavigationStack (Multi-step flows)**
```swift
NavigationStack(path: $viewModel.path) {
    // Root content
    .navigationDestination(for: OnboardingPath.self) { destination in
        // Destination views
    }
}
```

**3. Sheet/Modal (Overlays)**
```swift
.sheet(isPresented: $isShowingGive) {
    GiveScreen(viewModel: giveViewModel)
}
```

### ViewModel Pattern

ViewModels are used for complex, multi-screen flows:

```swift
@MainActor
class GiveViewModel: ObservableObject {
    @Published var enteredAmount: String = ""
    @Published var actionState: ButtonState = .normal

    let session: Session

    func giveAction() { /* ... */ }
}
```

Simple screens access Session/Controllers directly via `@EnvironmentObject`.

### FlipcashUI Components

| Category | Components |
|----------|------------|
| Buttons | `CodeButton`, `LargeButton`, `BorderedButton`, `CapsuleButton` |
| Containers | `Background`, `PartialSheet`, `BlurView`, `Row` |
| Dialog | `Dialog`, `DialogButton` |
| Modifiers | `.loading()`, `.if()`, `.badged()` |

### Theme

```swift
// Colors
Color.backgroundMain = Color(r: 0, g: 26, b: 12)  // Dark green
Color.textMain = .white
Color.mainAccent = .white

// Fonts
Font.appDisplayLarge  // 55pt bold
Font.appTextMedium    // 16pt bold
Font.appTextBody      // 16pt regular
```

---

## 8. Intent & Action System

### Intent Architecture

Intents model blockchain transactions as composable actions:

```
IntentType (protocol)
├── IntentTransfer
├── IntentSendCashLink
├── IntentReceiveCashLink
├── IntentWithdraw
└── IntentCreateAccount
        ↓
    ActionGroup (ordered actions)
        ↓
    ActionType (atomic operations)
├── ActionTransfer
├── ActionOpenAccount
├── ActionWithdraw
└── ActionFeePayment
```

### Transaction Signing Flow

```
Phase 1: Submit Actions
  Client submits Intent → Server validates → Returns ServerParameters

Phase 2: Apply & Sign
  Client applies parameters → Signs transactions → Sends signatures

Phase 3: Validation
  Server validates signatures → Broadcasts to blockchain
```

### Deep Linking

```swift
// Supported routes
/login      → Account switch
/c or /cash → Receive cash
/verify     → Email verification

// Fragment parsing
#e=<entropy>   → Base58-encoded mnemonic entropy
#p=<payload>   → Payment payload
```

### Bill State Machine

```swift
enum BillState {
    case .visible(.pop)   // Cash received (animates up)
    case .visible(.slide) // Cash sent (slides in)
    case .hidden(.slide)  // Dismissed
}
```

---

## 9. Controllers & Business Logic

### Controller Overview

| Controller | Purpose |
|------------|---------|
| `HistoryController` | Transaction history sync |
| `RatesController` | Exchange rates, currency preferences |
| `PushController` | APNs/FCM setup |
| `NotificationController` | System lifecycle events |
| `PoolController` | Betting pools (deprecated) |
| `StoreController` | In-app purchases |

### Polling Pattern

```swift
// RatesController - 55 second poll
private func registerPoller() {
    poller = Poller(seconds: 55, fireImmediately: true) { [weak self] in
        Task { try await self?.fetchExchangeRates() }
    }
}

// Session - 10 second poll
poller = Poller(seconds: 10, fireImmediately: true) { [weak self] in
    Task { await self?.poll() }
}
```

### Session Responsibilities

- Balance management (reactive via `Updateable`)
- Cash operations (send/receive bills)
- Transaction limits validation
- Toast/dialog presentation
- Post-transaction sync

### Preferences Persistence

```swift
// UserDefaults via @Defaults wrapper
@Defaults(.entryCurrency)
static var entryCurrency: CurrencyCode?

// Keychain via @SecureCodable wrapper
@SecureCodable(.keyAccount)
private var currentKeyAccount: KeyAccount?
```

---

## 10. Cryptography & Key Management

### CodeCurves (Ed25519)

Pure C implementation with Swift wrappers:

```swift
// Key generation
let keypair = KeyPair(seed: Seed32)
let keypair = KeyPair(mnemonic: phrase, path: .primary())

// Signing
let signature = keypair.sign(data)
```

### Key Derivation

```
BIP39 Mnemonic (12/24 words)
        ↓
SLIP-0010 Derivation (m/44'/501'/0'/0')
        ↓
KeyPair (PublicKey + PrivateKey)
        ↓
AccountCluster (per-mint accounts)
```

### Key Types

| Type | Size | Purpose |
|------|------|---------|
| `Seed32` | 32 bytes | Random entropy |
| `PublicKey` | 32 bytes | Account address |
| `PrivateKey` | 64 bytes | Signing key |
| `Signature` | 64 bytes | Transaction signature |

### AccountCluster

Groups keys for each token mint:

```swift
struct AccountCluster {
    let authority: DerivedKey      // Owner's derived key
    let timelock: TimelockDerivedAccounts

    var authorityPublicKey: PublicKey
    var vaultPublicKey: PublicKey
    var depositPublicKey: PublicKey
}
```

### Keychain Storage

```swift
// SecureCodable encodes to JSON, stores in Keychain
@SecureCodable(.keyAccount)
private var currentKeyAccount: KeyAccount?

// Stored keys:
// - .keyAccount (current)
// - .historicalAccounts (all past accounts)
// - .currentUserAccount (synced)
```

---

## 11. Transaction System

### Give (Send) Flow

```
GiveScreen → GiveViewModel.giveAction()
        ↓
Session.hasSufficientFunds() [validation]
        ↓
Session.showCashBill()
        ↓
SendCashOperation:
├── Opens message stream
├── Sends mint info to receiver
├── Waits for signed destination
├── Validates signature
├── Calls client.transfer()
└── Polls for completion
        ↓
Session.updatePostTransaction()
```

### Receive (Scan) Flow

```
ScanScreen [scans QR code]
        ↓
Session.receiveCash(payload)
        ↓
ScanCashOperation:
├── Listens for sender's mint info
├── Creates destination accounts
├── Sends signed destination
├── Polls for completion
└── Shows toast notification
```

### Activity Model

```swift
struct Activity {
    let id: PublicKey           // Transaction ID
    let state: State            // pending, completed
    let kind: Kind              // gave, received, cashLink, etc.
    let exchangedFiat: ExchangedFiat
    let date: Date
}
```

### Limit Checking

```swift
// Validate before send
session.hasSufficientFunds(for: amount) → SufficientFundsResult
session.hasLimitToSendFunds(for: amount) → Bool

// Limits refresh every 10 seconds
struct Limits {
    let sendLimits: [SendLimit]  // Per currency
    let depositLimit: DepositLimit?
}
```

---

## 12. Testing Patterns

### Framework: Swift Testing

```swift
import Testing

@Suite("Session Tests")
struct SessionTests {
    @Test
    static func testSufficientFunds_ExactMatch() {
        let balance = Quarks(quarks: 1_000_000, currencyCode: .usd, decimals: 6)
        #expect(balance.quarks == 1_000_000)
    }
}
```

### Mock Pattern

```swift
// Mocks defined as static properties
extension Session {
    static let mock = Session(
        container: .mock,
        historyController: .mock,
        ratesController: .mock,
        database: .mock,
        keyAccount: .mock,
        // ...
    )
}
```

### Running Tests

```bash
xcodebuild test -scheme Flipcash \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Test Coverage

| Area | Coverage |
|------|----------|
| Currency/Exchange | Excellent |
| Bonding Curve | Excellent |
| Session Logic | Good |
| ViewModels | Moderate |
| UI/Integration | Limited |

### Test Conventions

1. Use Swift Testing (`import Testing`), not XCTest
2. Name: `testFeature_Scenario_ExpectedResult`
3. Use `#expect()` with descriptive messages
4. Mark UI tests with `@MainActor`
5. Use `.mock` properties for dependencies

---

## Quick Reference

### Build Commands

```bash
# Build
xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS'

# Test
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 16'

# Clean
xcodebuild clean -scheme Flipcash
```

### Key Constants

```swift
PublicKey.usdc              // Main USDC mint
PublicKey.usdc.mintDecimals // 6 decimals

BondingCurve.startPrice     // $0.01
BondingCurve.endPrice       // $1,000,000
BondingCurve.maxSupply      // 21,000,000 tokens
```

### Hard Rules

1. **Never import CodeServices in Flipcash** - Use FlipcashCore
2. **Use Swift Testing** - Not XCTest
3. **Use exhaustive switch** - Not `if case` for enums
4. **Don't modify generated files** - Proto files are auto-generated
5. **Pools feature is deprecated** - Don't work on it

### Common Pitfalls

| Pitfall | Solution |
|---------|----------|
| Importing CodeServices | Use `import FlipcashCore` |
| Using XCTest | Use Swift Testing |
| Using `if case` for enums | Use exhaustive `switch` |
| Modifying proto files | Update service files instead |
| Adding unnecessary abstractions | Keep it simple |

---

## Getting Started Checklist

- [ ] Read `CLAUDE.md` for coding guidelines
- [ ] Understand Container/SessionContainer DI pattern
- [ ] Explore `Session.swift` - the main state hub
- [ ] Run tests to verify setup works
- [ ] Build and run on simulator
- [ ] Study one screen end-to-end (e.g., GiveScreen)

---

*This document was generated from comprehensive codebase analysis. For the latest guidelines, refer to `CLAUDE.md`.*
