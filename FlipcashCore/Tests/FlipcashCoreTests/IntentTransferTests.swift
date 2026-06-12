import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("IntentTransfer")
struct IntentTransferTests {

    // MARK: - Action Composition

    @Test("Transfer uses underlying amount from ExchangedFiat")
    func transferAmount() throws {
        let intent = try makeIntent(quarks: 3_000_000)

        let transfer = try #require(intent.actionGroup.actions[0] as? ActionTransfer)
        #expect(transfer.amount.quarks == 3_000_000)
    }

    @Test("Transfer uses correct source, destination, and mint")
    func transferActionProperties() throws {
        let cluster = AccountCluster.mock
        let destination = PublicKey.generate()!
        let intent = try makeIntent(
            sourceCluster: cluster,
            destination: destination
        )

        let transfer = try #require(intent.actionGroup.actions[0] as? ActionTransfer)
        #expect(transfer.source == cluster.vaultPublicKey)
        #expect(transfer.destination == destination)
        #expect(transfer.mint == PublicKey.usdf)
    }

    // MARK: - Metadata

    @Test("Metadata marks as non-withdrawal and non-remote-send with correct addresses")
    func metadataFlags() throws {
        let cluster = AccountCluster.mock
        let destination = PublicKey.generate()!
        let intent = try makeIntent(sourceCluster: cluster, destination: destination)
        let payment = intent.metadata().sendPublicPayment

        guard case .sendPublicPayment = intent.metadata().type else {
            Issue.record("Expected metadata type to be sendPublicPayment")
            return
        }

        #expect(payment.isWithdrawal == false)
        #expect(payment.isIndirectSend == false)
        #expect(payment.source == cluster.vaultPublicKey.solanaAccountID)
        #expect(payment.destination == destination.solanaAccountID)
    }

    @Test("Metadata includes exchange data")
    func metadataExchangeData() throws {
        let intent = try makeIntent(quarks: 2_500_000)
        let exchangeData = intent.metadata().sendPublicPayment.clientExchangeData

        #expect(exchangeData.quarks == 2_500_000)
        #expect(exchangeData.nativeAmount == 2.5)
    }

    @Test("Metadata includes reserve proto when provided")
    func metadataWithReserveProto() throws {
        let verifiedState = VerifiedState(
            rateProto: .makeTest(currencyCode: "usd", rate: 1.0),
            reserveProto: .makeTest(mint: .usdf)
        )

        let intent = try makeIntent(verifiedState: verifiedState)
        let exchangeData = intent.metadata().sendPublicPayment.clientExchangeData

        #expect(exchangeData.hasLaunchpadCurrencyReserveState)
    }

    @Test("Metadata omits reserve proto when nil")
    func metadataWithoutReserveProto() throws {
        let verifiedState = VerifiedState(
            rateProto: .makeTest(currencyCode: "usd", rate: 1.0)
        )

        let intent = try makeIntent(verifiedState: verifiedState)
        let exchangeData = intent.metadata().sendPublicPayment.clientExchangeData

        #expect(!exchangeData.hasLaunchpadCurrencyReserveState)
    }
}

// MARK: - Helpers

extension IntentTransferTests {

    // MARK: - App Metadata

    @Test("Metadata omits app metadata by default")
    func metadataOmitsAppMetadataByDefault() throws {
        let intent = try makeIntent()
        #expect(intent.metadata().hasAppMetadata == false)
    }

    @Test("Metadata carries serialized chat app metadata that decodes back")
    func metadataCarriesChatAppMetadata() throws {
        let chatID = ConversationID(data: Data(repeating: 0x05, count: 32))
        let chat = ChatPaymentMetadata(
            chatID: chatID,
            sourcePhoneE164: "+14155550100",
            destinationPhoneE164: "+14155550101"
        )
        let intent = try makeIntent(appMetadata: chat.serializedAppMetadata())

        let metadata = intent.metadata()
        #expect(metadata.hasAppMetadata)

        let decoded = try Flipcash_Intent_V1_AppMetadata(serializedBytes: metadata.appMetadata.value)
        guard case .chat(let chatMetadata)? = decoded.domain else {
            Issue.record("Expected chat domain metadata")
            return
        }
        #expect(chatMetadata.chatID.value == chatID.data)
        #expect(chatMetadata.contactDmPayment.source.value == "+14155550100")
        #expect(chatMetadata.contactDmPayment.destination.value == "+14155550101")
    }

    private func makeIntent(
        sourceCluster: AccountCluster = .mock,
        destination: PublicKey = .generate()!,
        quarks: UInt64 = 1_000_000,
        verifiedState: VerifiedState = VerifiedState(
            rateProto: .makeTest(currencyCode: "usd", rate: 1.0)
        ),
        appMetadata: Data? = nil
    ) throws -> IntentTransfer {
        let exchangedFiat = ExchangedFiat(
            nativeAmount: FiatAmount.usd(Decimal(quarks) / 1_000_000),
            rate: .oneToOne
        )

        return IntentTransfer(
            rendezvous: .generate()!,
            sourceCluster: sourceCluster,
            destination: destination,
            exchangedFiat: exchangedFiat,
            verifiedState: verifiedState,
            appMetadata: appMetadata
        )
    }
}

// MARK: - Test Support

private extension Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate {
    static func makeTest(currencyCode: String, rate: Double) -> Self {
        var proto = Self()
        proto.exchangeRate.currencyCode = currencyCode
        proto.exchangeRate.exchangeRate = rate
        return proto
    }
}

private extension Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState {
    static func makeTest(mint: PublicKey, supplyFromBonding: UInt64 = 0) -> Self {
        var proto = Self()
        proto.reserveState.mint = mint.solanaAccountID
        proto.reserveState.supplyFromBonding = supplyFromBonding
        return proto
    }
}
