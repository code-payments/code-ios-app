//
//  SwapInstructionBuilder.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation

/// Helper to construct buy/sell/swap transaction instructions following the standard patterns.
public struct SwapInstructionBuilder {
    
    // MARK: - Helper Methods
    
    /// Extracts compute budget and memo parameters from server response
    internal static func extractServerParameters(_ serverParameters: SwapResponseServerParameters) -> (
        payer: PublicKey,
        alts: [AddressLookupTable],
        computeUnitLimit: UInt32,
        computeUnitPrice: UInt64,
        memo: String,
        memoryAccount: PublicKey,
        memoryIndex: UInt32,
    ) {
        switch serverParameters.kind {
        case .stateless(let params):
            return (
                payer: params.payer,
                alts: params.alts,
                computeUnitLimit: params.computeUnitLimit,
                computeUnitPrice: params.computeUnitPrice,
                memo: params.memoValue,
                memoryAccount: params.memoryAccount,
                memoryIndex: params.memoryIndex
            )
        case .stateful(let params):
            return (
                payer: params.payer,
                alts: params.alts,
                computeUnitLimit: params.computeUnitLimit,
                computeUnitPrice: params.computeUnitPrice,
                memo: params.memoValue,
                memoryAccount: params.memoryAccount,
                memoryIndex: params.memoryIndex,
            )
        case .newCurrency:
            // New-currency launches use a dedicated builder
            // (SwapInstructionBuilder.newCurrencyLaunch) that consumes the
            // ReserveNewCurrency params directly and never calls this helper.
            fatalError("extractServerParameters cannot be used with a new-currency launch")
        case .stablecoin:
            // Stablecoin (USDF → USDC) withdraws use a dedicated instruction
            // builder that is not yet implemented and never calls this helper.
            fatalError("extractServerParameters cannot be used with a stablecoin withdraw")
        }
    }
}
