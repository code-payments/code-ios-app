//
//  CoinbaseDepositOperationTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@Suite("CoinbaseDepositOperation") @MainActor
struct CoinbaseDepositOperationTests {

    @Test("Deposit happy path creates a USDC order to the owner ATA and awaits Apple Pay success")
    func happyPath() async throws {
        let env = Env()
        let task = Task { try await env.op.start(amount: .tenUSDF) }

        try await waitUntil(env.op) { $0.state == .awaitingExternal(.applePay) }
        env.coinbaseService.receiveApplePayEvent(.fixture(.pollingSuccess))
        try await task.value

        #expect(env.ordering.createOrderCalls.count == 1)
        let request = try #require(env.ordering.createOrderCalls.first)
        #expect(request.purchaseCurrency == "USDC")
        #expect(request.destinationAddress == env.session.owner.authorityPublicKey.base58)
        #expect(env.op.state == .idle)
    }

    @Test("Amount below the $5 minimum is rejected before any order is created")
    func belowMinimum_rejected() async {
        let env = Env()
        await #expect(throws: DepositError.self) {
            try await env.op.start(amount: .threeUSDF)
        }
        #expect(env.ordering.createOrderCalls.isEmpty)
        #expect(env.op.state == .idle)
    }

    /// Regression: at 1.416385 CAD/USD the dialog renders the floor as
    /// "$7.08", but 7.08 CAD converts back to $4.9986 — the raw USD compare
    /// rejected the exact amount the dialog asked for. Entering the displayed
    /// minimum must pass the gate.
    @Test("Entering the displayed minimum in a non-USD currency passes the gate")
    func displayedMinimum_passesGate() async throws {
        let env = Env()
        let cad = Rate(fx: 1.416385, currency: .cad)
        let amount = ExchangedFiat(
            nativeAmount: FiatAmount(value: 7.08, currency: .cad),
            rate: cad
        )

        let task = Task { try await env.op.start(amount: amount) }
        try await waitUntil(env.op) { $0.state == .awaitingExternal(.applePay) }
        env.coinbaseService.receiveApplePayEvent(.fixture(.pollingSuccess))
        try await task.value

        #expect(env.ordering.createOrderCalls.count == 1)
    }

    @Test("Profile without verified phone+email throws requirementUnsatisfied")
    func profileNotVerified_throws() async {
        let env = Env(profile: Profile(displayName: nil, phone: Phone?.none, email: nil))
        await #expect(throws: DepositError.requirementUnsatisfied(.verifiedContact)) {
            try await env.op.start(amount: .tenUSDF)
        }
        #expect(env.ordering.createOrderCalls.isEmpty)
    }

    @Test("createOrder OnrampErrorResponse surfaces as externalRejected")
    func createOrder_onrampError_externalRejected() async throws {
        let env = Env()
        let errorResponse = try OnrampErrorResponse.fixture(errorType: "ERROR_CODE_GUEST_INVALID_CARD")
        env.ordering.createOrderHandler = { _ in throw errorResponse }
        await #expect(throws: DepositError.externalRejected(
            title: errorResponse.title,
            subtitle: errorResponse.subtitle
        )) {
            try await env.op.start(amount: .tenUSDF)
        }
    }

    @Test(
        "Apple Pay terminal error maps errorCode to OnrampErrorResponse.ErrorType and throws externalRejected",
        arguments: [
            (ApplePayEvent.Event.pollingError, "ERROR_CODE_GUEST_REGION_MISMATCH"),
            (ApplePayEvent.Event.commitError, "ERROR_CODE_GUEST_CARD_RISK_DECLINED"),
        ]
    )
    func applePayTerminalError_throwsExternalRejected(event: ApplePayEvent.Event, code: String) async throws {
        let env = Env()
        let task = Task { try await env.op.start(amount: .tenUSDF) }
        try await waitUntil(env.op) { $0.state == .awaitingExternal(.applePay) }
        env.coinbaseService.receiveApplePayEvent(.fixture(event, errorCode: code))

        let expectedType = OnrampErrorResponse.ErrorType(coinbaseCode: code)
        await #expect(throws: DepositError.externalRejected(
            title: expectedType.title,
            subtitle: expectedType.subtitle
        )) {
            try await task.value
        }
        #expect(env.op.state == .idle)
    }
}

// MARK: - Test environment

@MainActor
private struct Env {
    let session: MockSession
    let ordering: MockOnrampOrdering
    let coinbaseService: CoinbaseService
    let op: CoinbaseDepositOperation

    init(profile: Profile? = .verifiedFixture) {
        let session = MockSession(profile: profile)
        let ordering = MockOnrampOrdering()
        let coinbaseService = CoinbaseService(coinbase: ordering)
        self.session = session
        self.ordering = ordering
        self.coinbaseService = coinbaseService
        // Long timeout so the idle timer never fires during tests.
        self.op = CoinbaseDepositOperation(
            coinbaseService: coinbaseService,
            session: session,
            applePayIdleTimeout: .seconds(60)
        )
    }
}

private extension ExchangedFiat {
    static let tenUSDF = ExchangedFiat(nativeAmount: .usd(10), rate: .oneToOne)
    static let threeUSDF = ExchangedFiat(nativeAmount: .usd(3), rate: .oneToOne)
}
