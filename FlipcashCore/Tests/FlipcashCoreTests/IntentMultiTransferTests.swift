//
//  IntentMultiTransferTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("IntentMultiTransfer")
struct IntentMultiTransferTests {

    @Test("Emits one no-privacy transfer per payment, in order, from the source vault")
    func emitsOneTransferPerPayment() throws {
        let source = AccountCluster.mock
        let payments = [makePayment(quarks: 800_000), makePayment(quarks: 200_000)]
        let intent = try makeIntent(source: source, payments: payments)

        let actions = intent.actions.map { $0.action() }
        #expect(actions.map(\.id) == [0, 1])
        #expect(actions.map(\.noPrivacyTransfer.amount) == [800_000, 200_000])
        #expect(actions.map(\.noPrivacyTransfer.source) == Array(repeating: source.vaultPublicKey.solanaAccountID, count: 2))
        #expect(actions.map(\.noPrivacyTransfer.destination) == payments.map { $0.destination.solanaAccountID })
    }

    @Test("Metadata carries source, mint, and each payment's client exchange data")
    func metadataShape() throws {
        let source = AccountCluster.mock
        let payments = [makePayment(quarks: 800_000), makePayment(quarks: 200_000, owner: .generate()!)]
        let intent = try makeIntent(source: source, payments: payments)

        let metadata = intent.metadata().sendPublicMultiPayment
        #expect(metadata.source == source.vaultPublicKey.solanaAccountID)
        #expect(metadata.mint == PublicKey.usdf.solanaAccountID)
        #expect(metadata.payments.count == 2)
        #expect(metadata.payments.map(\.clientExchangeData.quarks) == [800_000, 200_000])
        #expect(metadata.payments[0].hasDestinationOwner == false)
        #expect(metadata.payments[1].hasDestinationOwner)
    }

    @Test("Rejects fewer than two and more than ten payments")
    func rejectsInvalidCounts() {
        #expect(throws: IntentMultiTransfer.Error.invalidPaymentCount) {
            try makeIntent(payments: [makePayment(quarks: 1)])
        }
        #expect(throws: IntentMultiTransfer.Error.invalidPaymentCount) {
            try makeIntent(payments: (0..<11).map { _ in makePayment(quarks: 1) })
        }
    }

    @Test("Rejects a repeated destination")
    func rejectsDuplicateDestination() {
        let first = makePayment(quarks: 1)
        #expect(throws: IntentMultiTransfer.Error.duplicateDestination) {
            try makeIntent(payments: [first, first])
        }
    }

    // MARK: - Helpers

    private func makePayment(quarks: UInt64, owner: PublicKey? = nil) -> IntentMultiTransfer.Payment {
        IntentMultiTransfer.Payment(
            destination: .generate()!,
            destinationOwner: owner,
            exchangedFiat: ExchangedFiat(
                nativeAmount: FiatAmount.usd(Decimal(quarks) / 1_000_000),
                rate: .oneToOne
            )
        )
    }

    private func makeIntent(source: AccountCluster = .mock, payments: [IntentMultiTransfer.Payment]) throws -> IntentMultiTransfer {
        var rate = Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate()
        rate.exchangeRate.currencyCode = "usd"
        rate.exchangeRate.exchangeRate = 1.0
        return try IntentMultiTransfer(
            rendezvous: .generate()!,
            sourceCluster: source,
            payments: payments,
            verifiedState: VerifiedState(rateProto: rate)
        )
    }
}
