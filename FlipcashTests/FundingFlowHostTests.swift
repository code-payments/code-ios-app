//
//  FundingFlowHostTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

@Suite("fundingPrompt(for:)") @MainActor
struct FundingFlowHostTests {

    @Test("Awaiting education maps to .phantomEducation")
    func education_mapsToPhantomEducation() {
        let prompt = fundingPrompt(for: .awaitingUserAction(.education(Self.samplePayment)))
        #expect(prompt == .phantomEducation)
    }

    @Test("Awaiting confirm maps to .phantomConfirm")
    func confirm_mapsToPhantomConfirm() {
        let prompt = fundingPrompt(for: .awaitingUserAction(.confirm(Self.samplePayment)))
        #expect(prompt == .phantomConfirm)
    }

    @Test("Non-user-action states produce no prompt", arguments: [
        FundingOperationState.idle,
        .working,
        .awaitingExternal(.phantom),
        .awaitingExternal(.applePay),
        .failed(reason: "test"),
    ])
    func passThroughStates_produceNoPrompt(state: FundingOperationState) {
        #expect(fundingPrompt(for: state) == nil)
    }

    // MARK: - Fixtures

    private static var samplePayment: PaymentOperation {
        .buy(.init(
            mint: .jeffy,
            currencyName: "TestCoin",
            amount: .mockOne,
            verifiedState: .fresh()
        ))
    }
}
