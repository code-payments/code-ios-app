//
//  ActivityHistoryResyncTests.swift
//  FlipcashCoreTests
//

import Testing
import GRPCCore
@testable import FlipcashCore

@Suite("Paged history resync classification")
struct ActivityHistoryResyncTests {

    // A stored paging cursor names a notification the server may later drop
    // (a history migration does exactly that). The server rejects the dead
    // token with a server-side failure rather than ignoring it, so the only
    // way a delta sync recovers is to start over with no cursor.

    @Test("A server-side failure warrants restarting history from the beginning")
    func serverFailureWarrantsResync() {
        #expect(ErrorFetchTransactionHistory.unknown.warrantsFullResync)
        #expect(ErrorFetchTransactionHistory.rejected.warrantsFullResync)
    }

    @Test("The INTERNAL a dead paging token produces classifies as resyncable")
    func serverInternalWarrantsResync() {
        // The observed failure: the swap migration dropped the notification the
        // stored cursor named, and the server answered the token with INTERNAL.
        let error = ErrorFetchTransactionHistory.from(
            transportError: RPCError(code: .internalError, message: "")
        )
        #expect(error == .unknown)
        #expect(error.warrantsFullResync)
    }

    @Test("Transient and terminal outcomes do not warrant a full resync")
    func otherOutcomesDoNotResync() {
        // Refetching all of history would be wasteful for a dropped
        // connection or a cancelled task, and pointless when denied.
        #expect(!ErrorFetchTransactionHistory.transportFailure.warrantsFullResync)
        #expect(!ErrorFetchTransactionHistory.cancelled.warrantsFullResync)
        #expect(!ErrorFetchTransactionHistory.denied.warrantsFullResync)
        #expect(!ErrorFetchTransactionHistory.ok.warrantsFullResync)
    }
}
