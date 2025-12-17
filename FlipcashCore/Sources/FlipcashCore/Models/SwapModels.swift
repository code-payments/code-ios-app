//
//  SwapModels.swift
//  FlipcashCore
//
//  Created by Claude.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

// MARK: - SwapId -

/// A unique identifier for a swap transaction, generated on the client.
public struct SwapId: Hashable, Codable, Sendable {
    
    public let value: Data
    
    /// Creates a SwapId from a PublicKey (32 bytes)
    public init(publicKey: PublicKey) {
        self.value = publicKey.data
    }
    
    /// Creates a SwapId from raw 32-byte data
    public init?(data: Data) {
        guard data.count == 32 else {
            return nil
        }
        self.value = data
    }
    
    /// Generates a random SwapId
    public static func generate() -> SwapId {
        SwapId(publicKey: .generate()!)
    }
    
    /// The SwapId as a PublicKey
    public var publicKey: PublicKey {
        try! PublicKey(value)
    }
}

// MARK: - Proto Conversion -

extension SwapId {
    public var codeSwapID: Code_Common_V1_SwapId {
        var swapID = Code_Common_V1_SwapId()
        swapID.value = value
        return swapID
    }
    
    public init?(_ proto: Code_Common_V1_SwapId) {
        self.init(data: proto.value)
    }
}

// MARK: - SwapState -

/// The lifecycle state of a swap transaction.
public enum SwapState: Int, Sendable {
    case unknown    = 0
    case created    = 1  // Swap state created, pending funding
    case funding    = 2  // VM swap PDA being funded
    case funded     = 3  // VM swap PDA funded, ready to execute
    case submitting = 4  // Swap transaction being submitted
    case finalized  = 5  // Swap completed on blockchain
    case failed     = 6  // Swap transaction failed
    case cancelling = 7  // Swap being cancelled
    case cancelled  = 8  // Swap cancelled, funds returned
}

extension SwapState {
    public init(_ proto: Code_Transaction_V2_SwapMetadata.State) {
        self = SwapState(rawValue: proto.rawValue) ?? .unknown
    }
    
    public var protoState: Code_Transaction_V2_SwapMetadata.State {
        Code_Transaction_V2_SwapMetadata.State(rawValue: rawValue) ?? .unknown
    }
}

// MARK: - FundingSource -

/// How swap funds are provided.
public enum FundingSource: Int, Sendable {
    case unknown = 0
    case submitIntent = 1  // Funded via SubmitIntent RPC
}

extension FundingSource {
    public init(_ proto: Code_Transaction_V2_FundingSource) {
        self = FundingSource(rawValue: proto.rawValue) ?? .unknown
    }
    
    public var protoSource: Code_Transaction_V2_FundingSource {
        Code_Transaction_V2_FundingSource(rawValue: rawValue) ?? .unknown
    }
}

// MARK: - VerifiedSwapMetadata -

/// Client-signed metadata to prevent tampering during swap execution.
public struct VerifiedSwapMetadata: Sendable {
    
    /// Client-provided parameters from StartSwap
    public let clientParameters: ClientParameters
    
    /// Server-agreed parameters from StartSwap
    public let serverParameters: ServerParameters
    
    public init(
        clientParameters: ClientParameters,
        serverParameters: ServerParameters
    ) {
        self.clientParameters = clientParameters
        self.serverParameters = serverParameters
    }
    
    public struct ClientParameters: Sendable {
        public let id: SwapId
        public let fromMint: PublicKey
        public let toMint: PublicKey
        public let amount: Quarks
        public let fundingSource: FundingSource
        public let fundingID: PublicKey
        
        public init(
            id: SwapId,
            fromMint: PublicKey,
            toMint: PublicKey,
            amount: Quarks,
            fundingSource: FundingSource,
            fundingID: PublicKey
        ) {
            self.id = id
            self.fromMint = fromMint
            self.toMint = toMint
            self.amount = amount
            self.fundingSource = fundingSource
            self.fundingID = fundingID
        }
    }
    
    public struct ServerParameters: Sendable {
        public let nonce: PublicKey
        public let blockhash: Hash
        
        public init(nonce: PublicKey, blockhash: Hash) {
            self.nonce = nonce
            self.blockhash = blockhash
        }
    }
}

// MARK: - Proto Conversion -

extension VerifiedSwapMetadata.ClientParameters {
    public init?(_ proto: Code_Transaction_V2_StartSwapRequest.Start.CurrencyCreator) {
        guard
            let swapId = SwapId(proto.id),
            let fromMint = try? PublicKey(proto.fromMint.value),
            let toMint = try? PublicKey(proto.toMint.value),
            let fundingID = try? PublicKey(base58: proto.fundingID)
        else {
            return nil
        }
        
        self.init(
            id: swapId,
            fromMint: fromMint,
            toMint: toMint,
            amount: Quarks(integerLiteral: proto.amount),
            fundingSource: FundingSource(proto.fundingSource),
            fundingID: fundingID
        )
    }
    
    public var proto: Code_Transaction_V2_StartSwapRequest.Start.CurrencyCreator {
        .with {
            $0.id = id.codeSwapID
            $0.fromMint = fromMint.solanaAccountID
            $0.toMint = toMint.solanaAccountID
            $0.amount = amount.quarks
            $0.fundingSource = fundingSource.protoSource
            $0.fundingID = fundingID.base58
        }
    }
}

extension VerifiedSwapMetadata.ServerParameters {
    public init?(_ proto: Code_Transaction_V2_StartSwapResponse.ServerParameters.CurrencyCreator) {
        guard
            let nonce = try? PublicKey(proto.nonce.value),
            let blockhash = try? Hash(proto.blockhash.value)
        else {
            return nil
        }
        
        self.init(nonce: nonce, blockhash: blockhash)
    }
    
    public var proto: Code_Transaction_V2_StartSwapResponse.ServerParameters.CurrencyCreator {
        .with {
            $0.nonce = nonce.solanaAccountID
            $0.blockhash = .with { $0.value = blockhash.data }
        }
    }
}

extension VerifiedSwapMetadata {
    public init?(_ proto: Code_Transaction_V2_VerifiedSwapMetadata) {
        guard case .currencyCreator(let verified) = proto.kind else {
            return nil
        }
        
        guard
            let clientParams = ClientParameters(verified.clientParameters),
            let serverParams = ServerParameters(verified.serverParameters)
        else {
            return nil
        }
        
        self.init(
            clientParameters: clientParams,
            serverParameters: serverParams
        )
    }
    
    public var proto: Code_Transaction_V2_VerifiedSwapMetadata {
        .with {
            $0.currencyCreator = .with {
                $0.clientParameters = clientParameters.proto
                $0.serverParameters = serverParameters.proto
            }
        }
    }
}

// MARK: - SwapMetadata -

/// Complete swap metadata including state and verification.
public struct SwapMetadata: Sendable {
    
    public let verifiedMetadata: VerifiedSwapMetadata
    public let state: SwapState
    public let signature: Signature
    
    public init(
        verifiedMetadata: VerifiedSwapMetadata,
        state: SwapState,
        signature: Signature
    ) {
        self.verifiedMetadata = verifiedMetadata
        self.state = state
        self.signature = signature
    }
    
    /// Convenience accessors
    public var swapId: SwapId {
        verifiedMetadata.clientParameters.id
    }
    
    public var fromMint: PublicKey {
        verifiedMetadata.clientParameters.fromMint
    }
    
    public var toMint: PublicKey {
        verifiedMetadata.clientParameters.toMint
    }
    
    public var amount: Quarks {
        verifiedMetadata.clientParameters.amount
    }
    
    public var nonce: PublicKey {
        verifiedMetadata.serverParameters.nonce
    }
    
    public var blockhash: Hash {
        verifiedMetadata.serverParameters.blockhash
    }
}

// MARK: - Proto Conversion -

extension SwapMetadata {
    public init?(_ proto: Code_Transaction_V2_SwapMetadata) {
        guard
            let verifiedMetadata = VerifiedSwapMetadata(proto.verifiedMetadata),
            let signature = try? Signature(proto.signature.value)
        else {
            return nil
        }
        
        self.init(
            verifiedMetadata: verifiedMetadata,
            state: SwapState(proto.state),
            signature: signature
        )
    }
    
    public var proto: Code_Transaction_V2_SwapMetadata {
        .with {
            $0.verifiedMetadata = verifiedMetadata.proto
            $0.state = state.protoState
            $0.signature = signature.proto
        }
    }
}

public struct SwapResponseServerParameters {
    public let kind: Kind
    
    public init(kind: Kind) {
        self.kind = kind
    }
    
    public enum Kind {
        case stateless(CurrencyCreatorStateless)
        case stateful(CurrencyCreatorStateful)
    }
    
    // Server parameters for stateless buy/sell flows
    public struct CurrencyCreatorStateless {
        public let payer: PublicKey
        public let recentBlockhash: Hash
        public let alts: [AddressLookupTable]
        public let computeUnitLimit: UInt32
        public let computeUnitPrice: UInt64
        public let memoValue: String
        public let memoryAccount: PublicKey
        public let memoryIndex: UInt32
        
        public init(
            payer: PublicKey,
            recentBlockhash: Hash,
            alts: [AddressLookupTable],
            computeUnitLimit: UInt32,
            computeUnitPrice: UInt64,
            memoValue: String,
            memoryAccount: PublicKey,
            memoryIndex: UInt32
        ) {
            self.payer = payer
            self.recentBlockhash = recentBlockhash
            self.alts = alts
            self.computeUnitLimit = computeUnitLimit
            self.computeUnitPrice = computeUnitPrice
            self.memoValue = memoValue
            self.memoryAccount = memoryAccount
            self.memoryIndex = memoryIndex
        }
    }
    
    // Server parameters for stateful buy/sell flows
    public struct CurrencyCreatorStateful: Sendable {
        public let payer: PublicKey
        public let alts: [AddressLookupTable]
        public let computeUnitLimit: UInt32
        public let computeUnitPrice: UInt64
        public let memoValue: String
        public let memoryAccount: PublicKey
        public let memoryIndex: UInt32
        
        public init(
            payer: PublicKey,
            alts: [AddressLookupTable],
            computeUnitLimit: UInt32,
            computeUnitPrice: UInt64,
            memoValue: String,
            memoryAccount: PublicKey,
            memoryIndex: UInt32
        ) {
            self.payer = payer
            self.alts = alts
            self.computeUnitLimit = computeUnitLimit
            self.computeUnitPrice = computeUnitPrice
            self.memoValue = memoValue
            self.memoryAccount = memoryAccount
            self.memoryIndex = memoryIndex
        }
    }
}

// MARK: - Proto Conversion -

extension SwapResponseServerParameters.CurrencyCreatorStateless {
    public init?(_ proto: Code_Transaction_V2_SwapResponse.ServerParameters.CurrencyCreatorStateless) {
        guard
            let payer = try? PublicKey(proto.payer.value),
            let recentBlockhash = try? Hash(proto.recentBlockhash.value),
            let memoryAccount = try? PublicKey(proto.memoryAccount.value)
        else {
            return nil
        }
        
        let alts = proto.alts.compactMap { AddressLookupTable($0) }
        
        self.init(
            payer: payer,
            recentBlockhash: recentBlockhash,
            alts: alts,
            computeUnitLimit: proto.computeUnitLimit,
            computeUnitPrice: proto.computeUnitPrice,
            memoValue: proto.memoValue,
            memoryAccount: memoryAccount,
            memoryIndex: proto.memoryIndex
        )
    }
    
    public var proto: Code_Transaction_V2_SwapResponse.ServerParameters.CurrencyCreatorStateless {
        .with {
            $0.payer = payer.solanaAccountID
            $0.recentBlockhash = .with { $0.value = recentBlockhash.data }
            $0.alts = alts.map { $0.proto }
            $0.computeUnitLimit = computeUnitLimit
            $0.computeUnitPrice = computeUnitPrice
            $0.memoValue = memoValue
            $0.memoryAccount = memoryAccount.solanaAccountID
            $0.memoryIndex = memoryIndex
        }
    }
}

extension SwapResponseServerParameters.CurrencyCreatorStateful {
    public init?(_ proto: Code_Transaction_V2_SwapResponse.ServerParameters.CurrencyCreatorStateful) {
        guard
            let payer = try? PublicKey(proto.payer.value),
            let memoryAccount = try? PublicKey(proto.memoryAccount.value)
        else {
            return nil
        }
        
        let alts = proto.alts.compactMap { AddressLookupTable($0) }
        
        self.init(
            payer: payer,
            alts: alts,
            computeUnitLimit: proto.computeUnitLimit,
            computeUnitPrice: proto.computeUnitPrice,
            memoValue: proto.memoValue,
            memoryAccount: memoryAccount,
            memoryIndex: proto.memoryIndex
        )
    }
    
    public var proto: Code_Transaction_V2_SwapResponse.ServerParameters.CurrencyCreatorStateful {
        .with {
            $0.payer = payer.solanaAccountID
            $0.alts = alts.map { $0.proto }
            $0.computeUnitLimit = computeUnitLimit
            $0.computeUnitPrice = computeUnitPrice
            $0.memoValue = memoValue
            $0.memoryAccount = memoryAccount.solanaAccountID
            $0.memoryIndex = memoryIndex
        }
    }
}

extension SwapResponseServerParameters {
    public init?(_ proto: Code_Transaction_V2_SwapResponse.ServerParameters) {
        switch proto.kind {
        case .currencyCreatorStateless(let stateless):
            guard let params = CurrencyCreatorStateless(stateless) else {
                return nil
            }
            self.init(kind: .stateless(params))
            
        case .currencyCreatorStateful(let stateful):
            guard let params = CurrencyCreatorStateful(stateful) else {
                return nil
            }
            self.init(kind: .stateful(params))
            
        case .none:
            return nil
        }
    }
    
    public var proto: Code_Transaction_V2_SwapResponse.ServerParameters {
        .with {
            switch kind {
            case .stateless(let params):
                $0.currencyCreatorStateless = params.proto
            case .stateful(let params):
                $0.currencyCreatorStateful = params.proto
            }
        }
    }
}

enum SwapDirection {
    case buy(mint: MintMetadata)                 // USDC -> Bonded Token
    case sell(mint: MintMetadata)                // Bonded Token -> USDC
    
    var sourceMint: MintMetadata {
        switch self {
        case .buy:
            return .usdc
        case .sell(let mint):
            return mint
        }
    }
        
    var destinationMint: MintMetadata {
        switch self {
        case .buy(let mint):
            return mint
        case .sell:
            return .usdc
        }
    }
}
