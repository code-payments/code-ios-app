//
//  Regression_6a0e1a1add5b5015cee68d6d.swift
//  FlipcashTests
//
//  EXC_BREAKPOINT: TokenAmount subtraction underflow inside
//  ExchangedFiat.subtractingFee, called from IntentWithdraw.init when the
//  on-chain fee exceeds the entered amount. Surfaces when balance < fee:
//  ExchangedFiat.compute(fromEntered:) silently caps the on-chain quarks to
//  balance, hasSufficientFunds passes because capped == balance, and
//  IntentWithdraw.init invokes subtractingFee unconditionally.
//
//  Fix: IntentWithdraw.init guards fee <= onChainAmount.quarks and throws
//  IntentWithdrawError.feeExceedsAmount when the precondition would fire.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Regression: 6a0e1a1 – IntentWithdraw underflow when fee exceeds amount", .bug("6a0e1a1add5b5015cee68d6d"))
struct Regression_6a0e1a1 {

    @Test("IntentWithdraw throws feeExceedsAmount when fee.quarks > onChainAmount.quarks instead of trapping")
    func intentWithdraw_throwsWhenFeeExceedsAmount() throws {
        // Reproduces the production scenario: $0.30 USDF balance, $0.50 fee.
        // The viewmodel's cap-to-balance path produces an on-chain amount
        // below the fee; before the fix, this trapped `TokenAmount.-`.
        let exchangedFiat = ExchangedFiat(
            nativeAmount: .usd(Decimal(0.30)),
            rate: .oneToOne
        )
        let fee = TokenAmount(quarks: 500_000, mint: .usdf)
        let destinationMetadata = DestinationMetadata(
            kind: .token,
            destination: PublicKey.generate()!,
            mint: .usdf,
            isValid: true,
            requiresInitialization: true,
            fee: fee
        )

        #expect(throws: IntentWithdrawError.feeExceedsAmount) {
            _ = try IntentWithdraw(
                sourceCluster: .mock,
                fee: fee,
                destinationMetadata: destinationMetadata,
                exchangedFiat: exchangedFiat,
                verifiedState: .fresh(bonded: false)
            )
        }
    }
}
