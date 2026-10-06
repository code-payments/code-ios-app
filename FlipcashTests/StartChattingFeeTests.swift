//
//  StartChattingFeeTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("StartChattingFee")
struct StartChattingFeeTests {

    private let presets = UserFlags.TipPresets(
        currency: .usd,
        minimum: Decimal(string: "0.25")!,
        low: 5,
        medium: 10,
        high: 20
    )

    private let rates: [CurrencyCode: Rate] = [
        .usd: Rate(fx: 1, currency: .usd),
        .cad: Rate(fx: Decimal(string: "1.37")!, currency: .cad),
    ]

    /// 0.33 USD is 0.4521 CAD: half-up would show 0.45, which sits under the fee.
    @Test("A fee shown in another currency rounds up, as the amount screen enforces")
    func feeInOtherCurrencyRoundsUp() {
        let fee = FiatAmount(value: Decimal(string: "0.33")!, currency: .usd)

        let amount = StartChattingFee.amount(
            recipientFee: fee,
            presets: presets,
            currency: .cad,
            rates: rates
        )

        #expect(amount == FiatAmount(value: Decimal(string: "0.46")!, currency: .cad))
        #expect(amount == TipFloor.toOpenDM(recipientFee: fee, presets: presets, in: .cad, rates: rates)?.displayed)
    }

    @Test("No fee falls back to the preset minimum")
    func nilFeeFallsBackToPresetMinimum() {
        let amount = StartChattingFee.amount(recipientFee: nil, presets: presets, currency: .usd, rates: rates)

        #expect(amount == FiatAmount(value: Decimal(string: "0.25")!, currency: .usd))
    }

    @Test("No fee and no presets gives nothing")
    func nilFeeAndNilPresetsIsNil() {
        let amount = StartChattingFee.amount(recipientFee: nil, presets: nil, currency: .usd, rates: rates)

        #expect(amount == nil)
    }
}
