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
        let payments = [makePayment(quarks: 800_000), makePayment(quarks: 200_000)]
        let intent = try makeIntent(source: source, payments: payments)

        let metadata = intent.metadata().sendPublicMultiPayment
        #expect(metadata.source == source.vaultPublicKey.solanaAccountID)
        #expect(metadata.mint == PublicKey.usdf.solanaAccountID)
        #expect(metadata.payments.count == 2)
        #expect(metadata.payments.map(\.clientExchangeData.quarks) == [800_000, 200_000])
    }

    @Test("Every payment carries its destination owner")
    func carriesDestinationOwners() throws {
        let payments = [makePayment(quarks: 800_000), makePayment(quarks: 200_000)]
        let intent = try makeIntent(payments: payments)

        let metadata = intent.metadata().sendPublicMultiPayment
        #expect(metadata.payments.allSatisfy { $0.hasDestinationOwner })
        #expect(metadata.payments.map(\.destinationOwner) == payments.map { $0.destinationOwner.solanaAccountID })
    }

    @Test("appMetadata is set when given and absent when not")
    func appMetadata() throws {
        let payments = [makePayment(quarks: 1), makePayment(quarks: 1)]
        let bytes = Data([1, 2, 3])

        let with = try makeIntent(payments: payments, appMetadata: bytes)
        #expect(with.metadata().hasAppMetadata)
        #expect(with.metadata().appMetadata.value == bytes)

        let without = try makeIntent(payments: payments)
        #expect(without.metadata().hasAppMetadata == false)
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

    @Test("Rejects a repeated destination owner")
    func rejectsDuplicateOwner() {
        let owner = PublicKey.generate()!
        #expect(throws: IntentMultiTransfer.Error.duplicateDestination) {
            try makeIntent(payments: [makePayment(quarks: 1, owner: owner), makePayment(quarks: 1, owner: owner)])
        }
    }

    @Test("Rejects a destination owner equal to the source authority")
    func rejectsOwnerEqualToSource() {
        let source = AccountCluster.mock
        #expect(throws: IntentMultiTransfer.Error.destinationIsSource) {
            try makeIntent(source: source, payments: [
                makePayment(quarks: 1, owner: source.authorityPublicKey),
                makePayment(quarks: 1),
            ])
        }
    }

    @Test("Rejects a destination equal to the source vault")
    func rejectsDestinationEqualToSourceVault() {
        let source = AccountCluster.mock
        #expect(throws: IntentMultiTransfer.Error.duplicateDestination) {
            try makeIntent(source: source, payments: [
                makePayment(quarks: 1, destination: source.vaultPublicKey),
                makePayment(quarks: 1),
            ])
        }
    }

    @Test("Rejects payments in different mints")
    func rejectsMintMismatch() {
        let other = makePayment(quarks: 1, fiat: ExchangedFiat(
            onChainAmount: TokenAmount(wholeTokens: 1, mint: .generate()!),
            nativeAmount: FiatAmount.usd(1),
            currencyRate: .oneToOne
        ))
        #expect(throws: IntentMultiTransfer.Error.mintMismatch) {
            try makeIntent(payments: [makePayment(quarks: 1), other])
        }
    }

    @Test("Rejects payments whose currency differs from the other payments or the verified rate")
    func rejectsCurrencyMismatch() {
        let cadFiat = ExchangedFiat(
            nativeAmount: FiatAmount(value: 1, currency: .cad),
            rate: Rate(fx: 1, currency: .cad)
        )
        let cad = makePayment(quarks: 1, fiat: cadFiat)
        #expect(throws: IntentMultiTransfer.Error.currencyMismatch) {
            try makeIntent(payments: [makePayment(quarks: 1), cad])
        }
        // Both payments agree with each other but not with the verified (usd) rate.
        #expect(throws: IntentMultiTransfer.Error.currencyMismatch) {
            try makeIntent(payments: [cad, makePayment(quarks: 1, fiat: cadFiat)])
        }
    }

    // MARK: - Helpers

    private func makePayment(
        quarks: UInt64,
        destination: PublicKey = .generate()!,
        owner: PublicKey = .generate()!,
        fiat: ExchangedFiat? = nil
    ) -> IntentMultiTransfer.Payment {
        IntentMultiTransfer.Payment(
            destination: destination,
            destinationOwner: owner,
            exchangedFiat: fiat ?? ExchangedFiat(
                nativeAmount: FiatAmount.usd(Decimal(quarks) / 1_000_000),
                rate: .oneToOne
            )
        )
    }

    private func makeIntent(source: AccountCluster = .mock, payments: [IntentMultiTransfer.Payment], appMetadata: Data? = nil) throws -> IntentMultiTransfer {
        var rate = Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate()
        rate.exchangeRate.currencyCode = "usd"
        rate.exchangeRate.exchangeRate = 1.0
        return try IntentMultiTransfer(
            rendezvous: .generate()!,
            sourceCluster: source,
            payments: payments,
            verifiedState: VerifiedState(rateProto: rate),
            appMetadata: appMetadata
        )
    }
}
