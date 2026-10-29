//
//  SwapMetadata+TestSupport.swift
//  FlipcashTests
//

import Foundation
@testable import FlipcashCore

extension SwapMetadata {
    static func makeTest(state: SwapState, swapId: SwapId = .generate()) -> SwapMetadata {
        SwapMetadata(
            verifiedMetadata: VerifiedSwapMetadata(
                clientParameters: VerifiedSwapMetadata.ClientParameters(
                    id: swapId,
                    fromMint: .usdf,
                    toMint: .jeffy,
                    amount: TokenAmount(quarks: 1_000_000, mint: .usdf),
                    fundingSource: .submitIntent(id: .jeffy)
                ),
                serverParameters: VerifiedSwapMetadata.ServerParameters(
                    nonce: .jeffy,
                    blockhash: try! Hash([UInt8](repeating: 3, count: 32))
                )
            ),
            state: state,
            signature: try! Signature(Array(repeating: Byte(0), count: 64))
        )
    }
}
