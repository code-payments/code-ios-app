# Swap RPC Analysis

**Date:** 2025-11-27
**Status:** Analysis Complete
**Related Files:** `FlipcashAPI/Sources/FlipcashAPI/proto/transaction/v2/transaction_service.proto`

---

## Overview

Analysis of new swap RPC changes introduced to support currency swapping via the Currency Creator program. The changes introduce a two-phase swap architecture with state management.

---

## New Proto Types

### SwapId
Client-generated 32-byte identifier for tracking swaps.

```protobuf
message SwapId {
    bytes value = 1; // 32 bytes
}
```

### FundingSource
Enum defining how swap funds are provided:
- `FUNDING_SOURCE_UNKNOWN = 0`
- `FUNDING_SOURCE_SUBMIT_INTENT = 1` - Funds via SubmitIntent RPC

### SwapMetadata.State
State machine for swap lifecycle:
```
CREATED    → Swap state created, pending funding
FUNDING    → VM swap PDA being funded
FUNDED     → VM swap PDA funded, ready to execute
SUBMITTING → Swap transaction being submitted
FINALIZED  → Swap completed on blockchain
FAILED     → Swap transaction failed
CANCELLING → Swap being cancelled
CANCELLED  → Swap cancelled, funds returned to VM
```

### VerifiedSwapMetadata
Client-signed metadata to prevent tampering. Contains:
- `client_parameters` - What client requested (StartSwapRequest.Start.CurrencyCreator)
- `server_parameters` - What server agreed to (StartSwapResponse.ServerParameters.CurrencyCreator)

---

## New RPCs

### StartSwap (Bidirectional Stream)
Begins swap process by coordinating verified metadata.

**Flow:**
```
Client                              Server
   |                                  |
   |-- Start (params + signature) --> |
   |                                  |
   |<-- ServerParameters (nonce, blockhash)
   |                                  |
   |-- SubmitSignature -------------> |  (signature of VerifiedSwapMetadata)
   |                                  |
   |<-- Success/Error ----------------|
```

**StartSwapRequest.Start.CurrencyCreator:**
- `id` - SwapId (client-generated)
- `from_mint` - Source token mint
- `to_mint` - Destination token mint
- `amount` - Amount in quarks
- `funding_source` - How funds are provided
- `funding_id` - Intent ID (base58) for tracking funding

**StartSwapResponse.ServerParameters.CurrencyCreator:**
- `nonce` - Reserved nonce account for durable transaction
- `blockhash` - Reserved blockhash for the nonce

### GetSwap (Unary)
Fetch metadata for a specific swap by ID.

### GetPendingSwaps (Unary)
Fetch all swaps pending client action:
1. Swaps in `CREATED` state needing SubmitIntent to fund
2. Swaps in `FUNDED` state needing Swap RPC to execute

### Swap (Bidirectional Stream) - Updated
Now supports both stateless (deprecated) and stateful variants.

**Stateful Initiate:**
- `swap_id` - The SwapId from StartSwap
- `owner` - Owner account
- `swap_authority` - One-time use authority for signing
- `signature` - Authentication signature

---

## Two-Phase Swap Architecture

### Phase 1: StartSwap (State Setup)
1. Client generates `SwapId`
2. Client calls `StartSwap` with parameters
3. Server reserves nonce + blockhash
4. Client signs `VerifiedSwapMetadata`
5. Server persists swap in `CREATED` state

### Phase 2: Fund + Execute
1. Client calls `SubmitIntent` with transfer to VM swap PDA
2. Server moves swap to `FUNDING` → `FUNDED`
3. Client calls `Swap` (stateful) with `swap_id`
4. Server provides full transaction parameters
5. Client builds + signs transaction
6. Server submits to blockchain
7. Swap moves to `SUBMITTING` → `FINALIZED`

---

## Transaction Instruction Format (Stateful)

### Buy Tokens (USDC → Custom Token)
```
1.  System::AdvanceNonce
2.  [Optional] ComputeBudget::SetComputeUnitLimit
3.  [Optional] ComputeBudget::SetComputeUnitPrice
4.  [Optional] Memo::Memo
5.  AssociatedTokenAccount::CreateIdempotent (Core Mint temp account)
6.  VM::TransferForSwap (Core Mint VM swap ATA → temp account)
7.  CurrencyCreator::BuyAndDepositIntoVm
8.  Token::CloseAccount (temp account)
9.  VM::CloseSwapAccountIfEmpty (swap ATA)
```

### Sell Tokens (Custom Token → USDC)
```
1.  System::AdvanceNonce
2.  [Optional] ComputeBudget::SetComputeUnitLimit
3.  [Optional] ComputeBudget::SetComputeUnitPrice
4.  [Optional] Memo::Memo
5.  AssociatedTokenAccount::CreateIdempotent (from_mint temp account)
6.  VM::TransferForSwap (from_mint VM swap ATA → temp account)
7.  CurrencyCreator::SellAndDepositIntoVm
8.  Token::CloseAccount (temp account)
9.  VM::CloseSwapAccountIfEmpty (swap ATA)
```

### Swap Tokens (Custom → Custom via USDC)
```
1.  System::AdvanceNonce
2.  [Optional] ComputeBudget::SetComputeUnitLimit
3.  [Optional] ComputeBudget::SetComputeUnitPrice
4.  [Optional] Memo::Memo
5.  AssociatedTokenAccount::CreateIdempotent (Core Mint temp account)
6.  AssociatedTokenAccount::CreateIdempotent (from_mint temp account)
7.  VM::TransferForSwap (from_mint VM swap ATA → temp account)
8.  CurrencyCreator::SellTokens (bounded sell → Core Mint temp)
9.  CurrencyCreator::BuyAndDepositIntoVm (unlimited buy → to_mint VM)
10. Token::CloseAccount (Core Mint temp)
11. Token::CloseAccount (from_mint temp)
12. VM::CloseSwapAccountIfEmpty (from_mint swap ATA)
```

---

## Stateful vs Stateless

| Aspect | Stateless (Deprecated) | Stateful |
|--------|------------------------|----------|
| First instruction | None (uses recent blockhash) | `System::AdvanceNonce` |
| Transaction validity | ~60 seconds (blockhash expiry) | Until nonce advanced |
| Use case | PoC only | Production |
| Server parameters | `recentBlockhash` | `nonce` + `blockhash` |

---

## Existing Infrastructure to Leverage

### From FlipcashCore
- `BidirectionalStreamReference` - Stream lifecycle management
- `TransactionService` - Pattern for streaming RPCs
- `IntentType` protocol - For funding intent
- `CompactMessage` - Signature construction
- Protobuf signing extension (`Message.sign(with:)`)

### From CodeServices (via FlipcashCore re-export)
- `SystemProgram.AdvanceNonce` - Durable nonce instruction
- `MemoProgram.Memo` - Memo instruction
- `ComputeBudgetProgram.SetComputeUnitLimit/Price` - Gas optimization
- `AssociatedTokenProgram.CreateAccount` - ATA creation
- `TokenProgram.CloseAccount` - Close token accounts
- `InstructionType` protocol - Instruction building pattern

---

## Components to Build

### Models (FlipcashCore/Models)
| Model | Description |
|-------|-------------|
| `SwapId` | 32-byte identifier wrapper |
| `SwapMetadata` | Full swap state with verified metadata |
| `VerifiedSwapMetadata` | Client-signed verification data |
| `SwapState` | State enum matching proto |

### Programs (FlipcashCore/Solana/Programs)
| Program | Instructions Needed |
|---------|---------------------|
| `VMProgram` | `TransferForSwap`, `CloseSwapAccountIfEmpty` |
| `CurrencyCreatorProgram` | `BuyAndDepositIntoVm`, `SellAndDepositIntoVm`, `SellTokens` |
| `AssociatedTokenProgram` | `CreateIdempotent` (different from `CreateAccount`) |

### Services (FlipcashCore/Clients)
| Component | Description |
|-----------|-------------|
| `TransactionService` extension or `SwapService` | Handle StartSwap + Swap streams |
| `FlipClient+Swap` | Async/await wrappers |

### Transaction Building
- Swap transaction builder following instruction format above
- Integration with server parameters (nonce, compute budget, memo, etc.)

---

## Open Questions

1. **CurrencyCreator program address** - Not yet in codebase
2. **VM instruction discriminators** - Command bytes for new VM instructions
3. **CreateIdempotent vs CreateAccount** - Need to verify if existing ATA instruction works or needs new variant

---

## References

- Proto file: `FlipcashAPI/Sources/FlipcashAPI/proto/transaction/v2/transaction_service.proto`
- Existing swap code: `CodeServices/Sources/CodeServices/Solana/Builder/TransactionBuilder.swift`
- Stream utilities: `FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Utilities/StreamReference.swift`
- Intent pattern: `FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Services/TransactionService.swift`
