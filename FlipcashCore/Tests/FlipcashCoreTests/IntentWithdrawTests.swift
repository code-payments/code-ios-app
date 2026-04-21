import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("IntentWithdraw")
struct IntentWithdrawTests {

    // MARK: - Action Composition

    @Test("Withdrawal with fee and initialization creates two actions with fee subtracted")
    func withdrawWithFeeAndInit() throws {
        let intent = try makeIntent(
            quarks: 5_000_000,
            feeQuarks: 500_000,
            requiresInitialization: true
        )

        #expect(intent.actionGroup.actions.count == 2)

        let transfer = try #require(intent.actionGroup.actions[0] as? ActionTransfer)
        let feeTransfer = try #require(intent.actionGroup.actions[1] as? ActionFeeTransfer)

        // Fee subtracted from withdrawal: 5.00 - 0.50 = 4.50
        #expect(transfer.amount.quarks == 4_500_000)
        #expect(feeTransfer.amount.quarks == 500_000)
    }

    @Test("Fee equal to full amount results in zero transfer amount")
    func withdrawFeeEqualsAmount() throws {
        let intent = try makeIntent(
            quarks: 500_000,
            feeQuarks: 500_000,
            requiresInitialization: true
        )

        let transfer = try #require(intent.actionGroup.actions[0] as? ActionTransfer)
        #expect(transfer.amount.quarks == 0)
    }

    // Note: a fee larger than the amount is now a precondition-fail in
    // TokenAmount subtraction, not a throwable error — callers are expected to
    // validate sufficient-funds before constructing a withdraw intent.

    @Test("Single transfer when fee condition is not met", arguments: [
        (feeQuarks: 500_000 as UInt64, requiresInit: false),
        (feeQuarks: 0 as UInt64, requiresInit: true),
    ])
    func singleTransferPath(feeQuarks: UInt64, requiresInit: Bool) throws {
        let intent = try makeIntent(
            quarks: 5_000_000,
            feeQuarks: feeQuarks,
            requiresInitialization: requiresInit
        )

        #expect(intent.actionGroup.actions.count == 1)

        let transfer = try #require(intent.actionGroup.actions[0] as? ActionTransfer)
        #expect(transfer.amount.quarks == 5_000_000)
    }

    // MARK: - Transfer Wiring

    @Test("Transfer uses correct source, destination, and mint")
    func transferSourceDestination() throws {
        let cluster = AccountCluster.mock
        let destination = PublicKey.generate()!
        let intent = try makeIntent(
            sourceCluster: cluster,
            destinationKey: destination,
            quarks: 1_000_000,
            feeQuarks: 0,
            requiresInitialization: false
        )

        let transfer = try #require(intent.actionGroup.actions[0] as? ActionTransfer)
        #expect(transfer.source == cluster.vaultPublicKey)
        #expect(transfer.destination == destination)
        #expect(transfer.mint == PublicKey.usdf)
    }

    // MARK: - Metadata

    @Test("Metadata produces correct withdrawal proto with exchange data")
    func metadata() throws {
        let intent = try makeIntent(quarks: 5_000_000, feeQuarks: 0, requiresInitialization: false)
        let metadata = intent.metadata()

        guard case .sendPublicPayment = metadata.type else {
            Issue.record("Expected sendPublicPayment metadata")
            return
        }

        #expect(metadata.sendPublicPayment.isWithdrawal == true)
        #expect(metadata.sendPublicPayment.isRemoteSend == false)

        let exchangeData = metadata.sendPublicPayment.clientExchangeData
        #expect(exchangeData.quarks == 5_000_000)
        #expect(exchangeData.nativeAmount == 5.0)
        #expect(exchangeData.hasCoreMintFiatExchangeRate)
    }

    @Test("Metadata includes destination owner when kind is owner")
    func metadataDestinationOwner() throws {
        let owner = PublicKey.generate()!

        let intent = try makeIntent(
            destinationKey: owner,
            quarks: 1_000_000,
            feeQuarks: 0,
            requiresInitialization: false,
            destinationKind: .owner
        )

        #expect(intent.metadata().sendPublicPayment.hasDestinationOwner)
    }
}

// MARK: - Helpers

extension IntentWithdrawTests {

    private func makeIntent(
        sourceCluster: AccountCluster = .mock,
        destinationKey: PublicKey = .generate()!,
        quarks: UInt64,
        feeQuarks: UInt64,
        requiresInitialization: Bool,
        verifiedState: VerifiedState = VerifiedState(
            rateProto: .makeTest(currencyCode: "usd", rate: 1.0)
        ),
        destinationKind: DestinationMetadata.Kind = .token
    ) throws -> IntentWithdraw {
        let exchangedFiat = ExchangedFiat(
            nativeAmount: FiatAmount.usd(Decimal(quarks) / 1_000_000),
            rate: .oneToOne
        )

        let fee = TokenAmount(quarks: feeQuarks, mint: .usdf)

        let destinationMetadata = DestinationMetadata(
            kind: destinationKind,
            destination: destinationKey,
            mint: .usdf,
            isValid: true,
            requiresInitialization: requiresInitialization,
            fee: fee
        )

        return try IntentWithdraw(
            sourceCluster: sourceCluster,
            fee: fee,
            destinationMetadata: destinationMetadata,
            exchangedFiat: exchangedFiat,
            verifiedState: verifiedState
        )
    }
}

// MARK: - Test Helpers

private extension Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate {
    static func makeTest(currencyCode: String, rate: Double) -> Self {
        var proto = Self()
        proto.exchangeRate.currencyCode = currencyCode
        proto.exchangeRate.exchangeRate = rate
        return proto
    }
}
