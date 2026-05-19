//
//  MockStatelessSwapping.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash
import FlipcashCore

/// Test fake for `StatelessSwapping`. Records calls and lets the test
/// substitute the next result (success or failure) to drive the catch path.
actor MockStatelessSwapping: StatelessSwapping {

    private(set) var callCount = 0
    private var nextResult: Result<StatelessSwapResult, Error> = .success(
        .finalized(signature: try! Signature(Data(repeating: 0, count: 64)))
    )

    func setNextResult(_ result: Result<StatelessSwapResult, Error>) {
        nextResult = result
    }

    func statelessSwap(
        fromMint: MintMetadata,
        toMint: MintMetadata,
        amount: TokenAmount,
        owner: KeyPair
    ) async throws -> StatelessSwapResult {
        callCount += 1
        return try nextResult.get()
    }
}
