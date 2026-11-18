//
//  Regression_6a7b33b.swift
//  Flipcash
//
//  Symptom:  Two users claiming one cash link at once: the loser's claim fails in the
//            server's transaction commit and returns gRPC INTERNAL, not
//            staleState(alreadyClaimed). Session.receiveCashLink reports it to Bugsnag
//            and shows "Something Went Wrong"; a retry then shows "Cash Already Collected".
//
//  Fix:      After an INTERNAL from the claim submit, CashLinkClaimRace re-reads the gift
//            card. If it is claimed, Session handles the error as already claimed.
//            Interim until the server returns STALE_STATE.
//

import Foundation
import Testing
import GRPCCore
@testable import FlipcashCore
@testable import Flipcash

@Suite("Regression: 6a7b33b – a cash link claim that loses the race reads as already collected")
struct Regression_6a7b33b {

    private struct Offline: Error {}

    private nonisolated final class Reader: GiftCardAccountReading, @unchecked Sendable {
        let result: Result<AccountInfo.ClaimState, Offline>
        var calls = 0

        init(_ result: Result<AccountInfo.ClaimState, Offline>) { self.result = result }

        func fetchAccountInfo(type: AccountInfoType, owner: KeyPair, requestingOwner: KeyPair?) async throws -> AccountInfo {
            calls += 1
            let state = try result.get()
            return AccountInfo(
                address: .usdf, mint: .usdf, owner: nil, authority: nil,
                balanceSource: .unknown, quarks: 0, managementState: .unknown,
                blockchainState: .unknown, claimState: state,
                exchangedFiat: nil, usdCostBasis: 0
            )
        }
    }

    private static let internalError = ErrorSubmitIntent.grpcStatus(RPCError(code: .internalError, message: "rpc server failure"))

    private func lostClaim(_ error: ErrorSubmitIntent, reader: Reader) async -> Bool {
        await CashLinkClaimRace.lostClaim(error, giftCard: .mock, requestingOwner: .mock, reader: reader)
    }

    @Test("INTERNAL with a claimed gift card is a lost claim")
    func internal_claimed() async {
        let reader = Reader(.success(.claimed))
        #expect(await lostClaim(Self.internalError, reader: reader))
        #expect(reader.calls == 1)
    }

    @Test("INTERNAL with a gift card that is not claimed stays a failure", arguments: [AccountInfo.ClaimState.notClaimed, .unknown, .expired])
    func internal_notClaimed(state: AccountInfo.ClaimState) async {
        let reader = Reader(.success(state))
        #expect(await lostClaim(Self.internalError, reader: reader) == false)
    }

    @Test("INTERNAL with a failed re-read stays a failure")
    func internal_rereadThrows() async {
        let reader = Reader(.failure(Offline()))
        #expect(await lostClaim(Self.internalError, reader: reader) == false)
    }

    @Test("Other errors never trigger the re-read", arguments: [
        ErrorSubmitIntent.grpcStatus(RPCError(code: .unavailable, message: "")),
        .unknown,
        .signatureError,
    ])
    func otherErrors(error: ErrorSubmitIntent) async {
        let reader = Reader(.success(.claimed))
        #expect(await lostClaim(error, reader: reader) == false)
        #expect(reader.calls == 0)
    }
}
