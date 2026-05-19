//
//  MockAssociatedTokenAccountFetching.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash
import FlipcashCore

/// Test fake for `AssociatedTokenAccountFetching`. Supports both an immediate
/// handler (return a fixture or throw) and a blocking handler that parks on a
/// continuation so the caller can drive the mock mid-fetch.
actor MockAssociatedTokenAccountFetching: AssociatedTokenAccountFetching {

    private(set) var callCount = 0

    private enum Mode {
        case immediate(@Sendable () throws -> AccountInfo?)
        case blocking(@Sendable () -> Void)
    }
    private var mode: Mode?
    private var pendingContinuation: CheckedContinuation<Result<AccountInfo?, Error>, Never>?

    func setImmediateHandler(_ handler: @escaping @Sendable () throws -> AccountInfo?) {
        mode = .immediate(handler)
    }

    func setBlockingHandler(_ onEntered: @escaping @Sendable () -> Void) {
        mode = .blocking(onEntered)
    }

    func resumeWith(_ result: Result<AccountInfo?, Error>) {
        pendingContinuation?.resume(returning: result)
        pendingContinuation = nil
    }

    func fetchAssociatedTokenAccount(owner: KeyPair, mint: PublicKey) async throws -> AccountInfo? {
        callCount += 1
        switch mode {
        case .immediate(let handler):
            return try handler()
        case .blocking(let onEntered):
            onEntered()
            let result: Result<AccountInfo?, Error> = await withCheckedContinuation { c in
                pendingContinuation = c
            }
            return try result.get()
        case nil:
            return nil
        }
    }
}
