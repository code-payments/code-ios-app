//
//  PaymentOperation+Fixtures.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash
import FlipcashCore

extension PaymentOperation.BuyPayload {

    /// Default buy payload for funding-operation tests. Override individual
    /// fields by re-using the standard memberwise initializer.
    static func fixture(
        mint: PublicKey = .jeffy,
        currencyName: String = "TestCoin",
        amount: ExchangedFiat = .mockOne,
        verifiedState: VerifiedState = .fresh()
    ) -> PaymentOperation.BuyPayload {
        PaymentOperation.BuyPayload(
            mint: mint,
            currencyName: currencyName,
            amount: amount,
            verifiedState: verifiedState
        )
    }
}

extension PaymentOperation.LaunchPayload {

    /// Default launch payload for funding-operation tests. `attestations`
    /// defaults to `.testFixture`; pass `nil` to exercise the
    /// missing-attestations rejection paths.
    static func fixture(
        currencyName: String = "NewCoin",
        total: ExchangedFiat = .mockOne,
        launchAmount: ExchangedFiat = .mockOne,
        launchFee: ExchangedFiat = .mockOne,
        attestations: PaymentOperation.LaunchAttestations? = .testFixture,
        verifiedState: VerifiedState? = nil,
        preLaunchedMint: PublicKey? = nil
    ) -> PaymentOperation.LaunchPayload {
        PaymentOperation.LaunchPayload(
            currencyName: currencyName,
            total: total,
            launchAmount: launchAmount,
            launchFee: launchFee,
            attestations: attestations,
            verifiedState: verifiedState,
            preLaunchedMint: preLaunchedMint
        )
    }
}

extension PaymentOperation.LaunchAttestations {

    /// Stand-in attestations for tests that don't exercise the moderation
    /// payload itself. The icon bytes are a minimal PNG signature so the
    /// shape of the data is "image-ish".
    static var testFixture: PaymentOperation.LaunchAttestations {
        PaymentOperation.LaunchAttestations(
            description: "Test description",
            billColors: ["#FFFFFF"],
            icon: Data([0x89, 0x50, 0x4E, 0x47]),
            nameAttestation: ModerationAttestation(rawValue: Data()),
            descriptionAttestation: ModerationAttestation(rawValue: Data()),
            iconAttestation: ModerationAttestation(rawValue: Data())
        )
    }
}
