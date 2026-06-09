//
//  TransportClassificationTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import GRPC
import GRPCCore
@testable import FlipcashCore

@Suite("Transport classification — classifiable errors route transient gRPC failures to a non-reportable case")
struct TransportClassificationTests {

    /// Generic contract check, reused by one `@Test` per conformer below. Using
    /// a generic over the concrete type (not a list of erased closures) keeps
    /// arguments `Sendable`-free and the call type-safe.
    private func assertClassifies<E: TransportClassifiableError>(_ type: E.Type) {
        // v1 (GRPCStatus) classification
        #expect(E.from(transportError: GRPCStatus(code: .deadlineExceeded, message: nil)).isReportable == false)
        #expect(E.from(transportError: GRPCStatus(code: .unavailable, message: nil)).isReportable == false)
        #expect(E.from(transportError: GRPCStatus(code: .internalError, message: nil)).isReportable == true)
        // v2 (RPCError) classification — identical semantics
        #expect(E.from(transportError: RPCError(code: .deadlineExceeded, message: "")).isReportable == false)
        #expect(E.from(transportError: RPCError(code: .unavailable, message: "")).isReportable == false)
        #expect(E.from(transportError: RPCError(code: .internalError, message: "")).isReportable == true)
    }

    // MARK: - Registry (one line per TransportClassifiableError conformer) -

    @Test func errorFetchBalance() { assertClassifies(ErrorFetchBalance.self) }

    @Test func errorRegisterAccount() { assertClassifies(ErrorRegisterAccount.self) }
    @Test func errorLoginAccount() { assertClassifies(ErrorLoginAccount.self) }
    @Test func errorFetchUserFlags() { assertClassifies(ErrorFetchUserFlags.self) }
    @Test func errorFetchUnauthenticatedUserFlags() { assertClassifies(ErrorFetchUnauthenticatedUserFlags.self) }
    @Test func errorFetchTransactionHistory() { assertClassifies(ErrorFetchTransactionHistory.self) }
    @Test func errorFetchTransactionHistoryItemsByID() { assertClassifies(ErrorFetchTransactionHistoryItemsByID.self) }
    @Test func errorAddToken() { assertClassifies(ErrorAddToken.self) }
    @Test func errorDeleteToken() { assertClassifies(ErrorDeleteToken.self) }
    @Test func errorUpdateSettings() { assertClassifies(ErrorUpdateSettings.self) }
    @Test func errorFetchJWT() { assertClassifies(ErrorFetchJWT.self) }
    @Test func errorSendEmailCode() { assertClassifies(ErrorSendEmailCode.self) }
    @Test func errorCheckEmailCode() { assertClassifies(ErrorCheckEmailCode.self) }
    @Test func errorUnlinkEmail() { assertClassifies(ErrorUnlinkEmail.self) }
    @Test func errorFetchProfile() { assertClassifies(ErrorFetchProfile.self) }
    @Test func errorRateHistory() { assertClassifies(ErrorRateHistory.self) }
    @Test func errorGetSwap() { assertClassifies(ErrorGetSwap.self) }
    @Test func errorVoidGiftCard() { assertClassifies(ErrorVoidGiftCard.self) }
    @Test func errorFetchLimits() { assertClassifies(ErrorFetchLimits.self) }
    @Test func errorFetchIntentMetadata() { assertClassifies(ErrorFetchIntentMetadata.self) }
    @Test func errorSendVerificationCode() { assertClassifies(ErrorSendVerificationCode.self) }
    @Test func errorCheckVerificationCode() { assertClassifies(ErrorCheckVerificationCode.self) }
    @Test func errorUnlinkPhone() { assertClassifies(ErrorUnlinkPhone.self) }

    // MARK: - Tier 2: associated-value errors that capture the transport status -
    // These don't conform to TransportClassifiableError (they carry the status
    // in a case rather than mapping to a dedicated one), so their `isReportable`
    // is asserted directly.

    @Test("ErrorModeration.network is reportable only for non-transient statuses")
    func errorModerationNetwork() {
        #expect(ErrorModeration.network(GRPCStatus(code: .deadlineExceeded, message: nil)).isReportable == false)
        #expect(ErrorModeration.network(GRPCStatus(code: .internalError, message: nil)).isReportable == true)
        #expect(ErrorModeration.unknown.isReportable == true)
    }

    @Test("ErrorLaunchCurrency.network is reportable only for non-transient statuses")
    func errorLaunchCurrencyNetwork() {
        #expect(ErrorLaunchCurrency.network(GRPCStatus(code: .deadlineExceeded, message: nil)).isReportable == false)
        #expect(ErrorLaunchCurrency.network(GRPCStatus(code: .internalError, message: nil)).isReportable == true)
        #expect(ErrorLaunchCurrency.unknown.isReportable == true)
    }

    @Test("ErrorSwap classifies grpcStatus by transience; grpcError always reports")
    func errorSwapGRPCStatus() {
        #expect(ErrorSwap.grpcStatus(RPCError(code: .deadlineExceeded, message: "")).isReportable == false)
        #expect(ErrorSwap.grpcStatus(RPCError(code: .internalError, message: "")).isReportable == true)
        // .grpcError is the un-typed failure — deliberately reportable even for a
        // transient-looking status, unlike the typed .grpcStatus case.
        #expect(ErrorSwap.grpcError(RPCError(code: .unavailable, message: "")).isReportable == true)
        #expect(ErrorSwap.unknown.isReportable == true)
    }

    @Test("ErrorStatelessSwap classifies grpcStatus by transience; grpcError always reports")
    func errorStatelessSwapGRPCStatus() {
        #expect(ErrorStatelessSwap.grpcStatus(RPCError(code: .deadlineExceeded, message: "")).isReportable == false)
        #expect(ErrorStatelessSwap.grpcStatus(RPCError(code: .internalError, message: "")).isReportable == true)
        #expect(ErrorStatelessSwap.grpcError(RPCError(code: .unavailable, message: "")).isReportable == true)
        #expect(ErrorStatelessSwap.unknown.isReportable == true)
    }

    // MARK: - Raw GRPCStatus self-classification -
    // Unary RPCs whose failure type is the existential `Error` ship the status
    // directly; its `ServerError` conformance classifies transient transport
    // failures as non-reportable without a dedicated error enum.

    @Test("GRPCStatus is reportable only for non-transient statuses")
    func grpcStatusReportability() {
        #expect(GRPCStatus(code: .deadlineExceeded, message: nil).isReportable == false)
        #expect(GRPCStatus(code: .unavailable, message: nil).isReportable == false)
        #expect(GRPCStatus(code: .internalError, message: nil).isReportable == true)
        #expect(GRPCStatus(code: .cancelled, message: nil).isReportable == true)
    }

    // MARK: - Raw RPCError self-classification (gRPC v2) -
    // The v2 equivalent of the GRPCStatus self-classification above: transient
    // transport codes stay non-reportable so they never reach Bugsnag.

    @Test("RPCError is reportable only for non-transient codes")
    func rpcErrorReportability() {
        #expect(RPCError(code: .deadlineExceeded, message: "").isReportable == false)
        #expect(RPCError(code: .unavailable, message: "").isReportable == false)
        #expect(RPCError(code: .internalError, message: "").isReportable == true)
        #expect(RPCError(code: .cancelled, message: "").isReportable == true)
    }

    // MARK: - Real transport errors -

    @Test("A real gRPC RPCTimedOut normalizes to a non-reportable transport status")
    func rpcTimedOutClassifiesAsNonReportable() {
        // The unary wrapper routes NIO/gRPC errors through makeGRPCStatus() before
        // classifying; a real RPC timeout must surface as .deadlineExceeded so it
        // lands in the transient, non-reportable bucket.
        let status = GRPCError.RPCTimedOut(.deadline(.now())).makeGRPCStatus()
        #expect(status.code == .deadlineExceeded)
        #expect(status.isReportable == false)
    }
}
