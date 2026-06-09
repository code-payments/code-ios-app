//
//  TransportClassificationTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import GRPCCore
@testable import FlipcashCore

@Suite("Transport classification — classifiable errors route transient gRPC failures to a non-reportable case")
struct TransportClassificationTests {

    /// Generic contract check, reused by one `@Test` per conformer below. Using
    /// a generic over the concrete type (not a list of erased closures) keeps
    /// arguments `Sendable`-free and the call type-safe.
    private func assertClassifies<E: TransportClassifiableError>(_ type: E.Type) {
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

    // MARK: - Tier 2: associated-value errors that capture the transport error -
    // These don't conform to TransportClassifiableError (they carry the error in a
    // case rather than mapping to a dedicated one), so their `isReportable` is
    // asserted directly.

    @Test("ErrorModeration.network is reportable only for non-transient errors")
    func errorModerationNetwork() {
        #expect(ErrorModeration.network(RPCError(code: .deadlineExceeded, message: "")).isReportable == false)
        #expect(ErrorModeration.network(RPCError(code: .internalError, message: "")).isReportable == true)
        #expect(ErrorModeration.unknown.isReportable == true)
    }

    @Test("ErrorLaunchCurrency.network is reportable only for non-transient errors")
    func errorLaunchCurrencyNetwork() {
        #expect(ErrorLaunchCurrency.network(RPCError(code: .deadlineExceeded, message: "")).isReportable == false)
        #expect(ErrorLaunchCurrency.network(RPCError(code: .internalError, message: "")).isReportable == true)
        #expect(ErrorLaunchCurrency.unknown.isReportable == true)
    }

    @Test("ErrorSwap classifies grpcStatus by transience; grpcError always reports")
    func errorSwapClassification() {
        #expect(ErrorSwap.grpcStatus(RPCError(code: .deadlineExceeded, message: "")).isReportable == false)
        #expect(ErrorSwap.grpcStatus(RPCError(code: .internalError, message: "")).isReportable == true)
        // .grpcError is the un-typed failure — deliberately reportable even for a
        // transient-looking code, unlike the typed .grpcStatus case.
        #expect(ErrorSwap.grpcError(RPCError(code: .unavailable, message: "")).isReportable == true)
        #expect(ErrorSwap.unknown.isReportable == true)
    }

    @Test("ErrorStatelessSwap classifies grpcStatus by transience; grpcError always reports")
    func errorStatelessSwapClassification() {
        #expect(ErrorStatelessSwap.grpcStatus(RPCError(code: .deadlineExceeded, message: "")).isReportable == false)
        #expect(ErrorStatelessSwap.grpcStatus(RPCError(code: .internalError, message: "")).isReportable == true)
        #expect(ErrorStatelessSwap.grpcError(RPCError(code: .unavailable, message: "")).isReportable == true)
        #expect(ErrorStatelessSwap.unknown.isReportable == true)
    }

    // MARK: - Raw RPCError self-classification -
    // Unary RPCs whose failure type is the existential `Error` ship the RPCError
    // directly; its `ServerError` conformance classifies transient transport
    // failures as non-reportable without a dedicated error enum.

    @Test("RPCError is reportable only for non-transient codes")
    func rpcErrorReportability() {
        #expect(RPCError(code: .deadlineExceeded, message: "").isReportable == false)
        #expect(RPCError(code: .unavailable, message: "").isReportable == false)
        #expect(RPCError(code: .internalError, message: "").isReportable == true)
        #expect(RPCError(code: .cancelled, message: "").isReportable == true)
    }
}
