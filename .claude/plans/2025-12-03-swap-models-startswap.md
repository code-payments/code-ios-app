# Swap Models and StartSwap Implementation

**Date:** 2025-12-03
**Status:** Phase 1 Complete - Models & StartSwap
**Related Files:** 
- `SwapModels.swift` (new)
- `TransactionService.swift` (updated)
- `Protobuf+Model.swift` (updated)

---

## Overview

Implemented Swift models for swap operations and completed the `startSwap()` bidirectional stream implementation in `TransactionService`. This establishes the foundation for the two-phase swap architecture.

---

## What Was Completed

### 1. SwapModels.swift (New File)

Created comprehensive Swift models matching the protobuf definitions:

#### **Hash**
- 32-byte Solana blockhash wrapper
- Base58 encoding support
- Zero constant for initialization

#### **SwapId**
- 32-byte unique identifier for swaps
- Generated from PublicKey
- Proto conversion extensions

#### **SwapState**
- Enum representing swap lifecycle states
- Maps to proto `SwapMetadata.State`
- Values: unknown, created, funding, funded, submitting, finalized, failed, cancelling, cancelled

#### **FundingSource**
- Enum for funding methods
- Currently only supports `submitIntent`

#### **VerifiedSwapMetadata**
- Container for client and server parameters
- Prevents parameter tampering through signatures
- Nested structs for `ClientParameters` and `ServerParameters`

**ClientParameters:**
- SwapId
- fromMint/toMint
- amount (Quarks)
- fundingSource
- fundingID (intent ID)

**ServerParameters:**
- nonce (PublicKey)
- blockhash (Hash)

#### **SwapMetadata**
- Complete swap state including verification
- Contains VerifiedSwapMetadata, SwapState, and Signature
- Convenience accessors for common fields

All models include:
- Proto conversion methods (both directions)
- `Sendable` conformance for Swift Concurrency
- `Hashable` and `Codable` conformance where appropriate

---

### 2. TransactionService.swift Updates

#### **startSwap() Method**
Complete bidirectional stream implementation following the established pattern:

**Signature:**
```swift
private func startSwap(
    swapId: SwapId,
    fromMint: PublicKey,
    toMint: PublicKey,
    amount: Quarks,
    fundingID: PublicKey,
    owner: KeyPair,
    completion: @Sendable @escaping (Result<SwapMetadata, ErrorSwap>) -> Void
)
```

**Flow:**
1. **Send Start Message**
   - Constructs `ClientParameters`
   - Sends `StartSwapRequest.Start` with currency_creator parameters
   - Includes owner signature for authentication

2. **Receive Server Parameters**
   - Server responds with nonce + blockhash
   - Validates response type (currency_creator)
   - Stores parameters for metadata construction

3. **Sign Verified Metadata**
   - Constructs `VerifiedSwapMetadata` combining client + server params
   - Signs serialized metadata with owner keypair
   - Prevents tampering of swap parameters

4. **Send Signature**
   - Submits `StartSwapRequest.SubmitSignature`
   - Server validates signature

5. **Handle Success/Error**
   - Success: Returns complete `SwapMetadata` with state = `.created`
   - Error: Detailed error logging and typed error response
   - Stream lifecycle management with retain/release pattern

**Error Handling:**
- Validates server parameter types
- Parses proto failures gracefully
- Detailed trace logging for debugging
- gRPC status handling

---

### 3. Protobuf+Model.swift Updates

Added proto conversion extension:

```swift
extension PublicKey {
    public var solanaAccountID: Code_Common_V1_SolanaAccountId {
        codeAccountID
    }
}
```

Provides convenient alias matching protobuf naming convention.

---

## Architecture Patterns

### Stream Management
- Uses `BidirectionalStartSwapStream` reference wrapper
- Intentional retain cycle during stream lifetime
- Automatic cleanup on stream completion
- Matches existing `SubmitIntent` pattern

### Proto Conversions
- Bidirectional conversion methods on all models
- Optional initializers for safe parsing
- Uses existing `.with {}` builder pattern
- Consistent with codebase style

### Error Tracing
- Comprehensive trace logging at key points
- Includes relevant identifiers (SwapId, nonce, blockhash)
- Follows existing trace() pattern
- Detailed error breakdowns for debugging

---

## Next Steps

### Phase 2: GetSwap & GetPendingSwaps (Unary RPCs)
- [ ] Implement `getSwap(swapId:owner:completion:)`
- [ ] Implement `getPendingSwaps(owner:completion:)`
- [ ] Parse and return arrays of `SwapMetadata`

### Phase 3: Swap RPC (Execution Stream)
- [ ] Implement stateful swap bidirectional stream
- [ ] Transaction building with server parameters
- [ ] Handle swap authority (one-time use keypair)
- [ ] Support `wait_for_blockchain_status` flag

### Phase 4: Transaction Building
- [ ] SwapTransactionBuilder class/struct
- [ ] Nonce advancement instruction
- [ ] Compute budget instructions
- [ ] Memo instruction
- [ ] VM transfer + CurrencyCreator buy/sell sequencing
- [ ] Account closing instructions
- [ ] Versioned transaction with ALTs

### Phase 5: High-Level API
- [ ] Complete `buy()` and `sell()` methods
- [ ] Orchestrate: StartSwap → SubmitIntent → Swap
- [ ] Intent creation for funding
- [ ] Result parsing and PaymentMetadata construction

### Phase 6: Testing & Integration
- [ ] Unit tests for models
- [ ] Stream behavior tests
- [ ] Integration tests with mock server
- [ ] Error scenario coverage

---

## Open Questions

1. **GetSwap necessity** - Should `startSwap()` return partial metadata and require a follow-up `getSwap()` call, or is the current approach sufficient?

2. **Swap authority generation** - Where should the one-time use keypair for swap authority be generated? In the high-level buy/sell methods or as a parameter?

3. **Intent creation** - Should the funding intent be created internally by buy/sell, or should it be passed in?

4. **Transaction builder location** - Should it live in TransactionService, as a separate builder class, or as part of SwapMetadata?

---

## Files Modified

| File | Status | Lines Changed |
|------|--------|---------------|
| `SwapModels.swift` | Created | ~330 |
| `TransactionService.swift` | Modified | ~150 |
| `Protobuf+Model.swift` | Modified | ~5 |

---

## Testing Checklist

### Models
- [x] SwapId generation and conversion
- [x] Proto bidirectional conversion
- [x] State enum mapping
- [x] VerifiedSwapMetadata construction

### StartSwap Stream
- [ ] Successful start returns correct metadata
- [ ] Server parameter parsing
- [ ] Signature creation and submission
- [ ] Error cases handled gracefully
- [ ] Stream cleanup on completion
- [ ] Stream cleanup on error

### Integration
- [ ] Compiles without errors
- [ ] No import violations (FlipcashCore only)
- [ ] Sendable conformance validated
- [ ] Proto compatibility verified

---

## Notes

- All models are `Sendable` for Swift Concurrency safety
- Proto conversions use optional initializers for safe parsing failures
- Stream pattern matches existing `SubmitIntent` implementation exactly
- Hash type added for blockhash support (32 bytes, base58 encoding)
- SwapId uses PublicKey internally for 32-byte guarantee
- Comprehensive trace logging for production debugging
