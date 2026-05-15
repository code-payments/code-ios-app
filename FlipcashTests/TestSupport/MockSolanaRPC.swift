//
//  MockSolanaRPC.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash
import FlipcashCore

/// Test fake for `SolanaRPC`. Defaults to "everything succeeds silently" —
/// simulate returns an empty result, sendTransaction returns `Signature.mock`.
/// Tests override the handlers when they need to drive an error path.
final class MockSolanaRPC: SolanaRPC, @unchecked Sendable {

    nonisolated(unsafe) var simulateHandler: (@Sendable (String) async throws -> SolanaSimulationResult)?
    nonisolated(unsafe) var sendHandler: (@Sendable (String) async throws -> Signature)?
    nonisolated(unsafe) var blockhashHandler: (@Sendable (SolanaCommitment) async throws -> Hash)?

    init() {}

    func getLatestBlockhash(commitment: SolanaCommitment) async throws -> Hash {
        if let handler = blockhashHandler {
            return try await handler(commitment)
        }
        return Hash.mock
    }

    func simulateTransaction(
        _ base64Transaction: String,
        configuration: SolanaSimulateTransactionConfig
    ) async throws -> SolanaSimulationResult {
        if let handler = simulateHandler {
            return try await handler(base64Transaction)
        }
        return SolanaSimulationResult(err: nil, logs: nil)
    }

    func sendTransaction(
        _ base64Transaction: String,
        configuration: SolanaSendTransactionConfig
    ) async throws -> Signature {
        if let handler = sendHandler {
            return try await handler(base64Transaction)
        }
        return Signature.mock
    }
}
