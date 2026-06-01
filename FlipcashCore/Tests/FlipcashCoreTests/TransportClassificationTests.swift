//
//  TransportClassificationTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import GRPC
@testable import FlipcashCore

@Suite("Transport classification — classifiable errors route transient gRPC failures to a non-reportable case")
struct TransportClassificationTests {

    /// Generic contract check, reused by one `@Test` per conformer below. Using
    /// a generic over the concrete type (not a list of erased closures) keeps
    /// arguments `Sendable`-free and the call type-safe.
    private func assertClassifies<E: TransportClassifiableError>(_ type: E.Type) {
        #expect(E.from(transportError: GRPCStatus(code: .deadlineExceeded, message: nil)).isReportable == false)
        #expect(E.from(transportError: GRPCStatus(code: .unavailable, message: nil)).isReportable == false)
        #expect(E.from(transportError: GRPCStatus(code: .internalError, message: nil)).isReportable == true)
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

    @Test("ErrorSwap.grpcStatus is reportable only for non-transient statuses")
    func errorSwapGRPCStatus() {
        #expect(ErrorSwap.grpcStatus(GRPCStatus(code: .deadlineExceeded, message: nil)).isReportable == false)
        #expect(ErrorSwap.grpcStatus(GRPCStatus(code: .internalError, message: nil)).isReportable == true)
        #expect(ErrorSwap.unknown.isReportable == true)
    }

    @Test("ErrorStatelessSwap suppresses transport-failure reporting")
    func errorStatelessSwapTransport() {
        #expect(ErrorStatelessSwap.grpcStatus(GRPCStatus(code: .deadlineExceeded, message: nil)).isReportable == false)
        #expect(ErrorStatelessSwap.unknown.isReportable == true)
    }
}
