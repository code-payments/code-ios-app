//
//  Regression_6aac6bdf6293b02dff667d25.swift
//  Flipcash
//
//  Bug: "Failed to set minimum tip" with `ErrorSetMinDmChatInitFee.invalidAmount`.
//       Minimum To Chat floored the fee at 1 unit of the balance currency, a
//       fraction of a cent in IDR, NGN, or JMD. The entry passed locally, the
//       server refused it, and the dialog repeated the 1-unit floor under an
//       amount that already cleared it, so users retried.
//
//  Fix: the screen judges the fee against the server's regional tip minimum
//       (the entry currency's preset row, or the USD fallback) and names that
//       floor in the dialog.
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Regression: 6aac6bd – Minimum To Chat accepts a fee under the regional minimum", .bug("6aac6bdf6293b02dff667d25"))
struct Regression_6aac6bd {

    private let jmdPresets = UserFlags.TipPresets(currency: .jmd, minimum: 150, low: 500, medium: 1000, high: 2000)
    private let usdPresets = UserFlags.TipPresets(currency: .usd, minimum: 1, low: 5, medium: 10, high: 20)
    private let jmdRate = Rate(fx: 157, currency: .jmd)
    private let idrRate = Rate(fx: 16000, currency: .idr)

    @Test("A fee under the currency's own preset minimum is refused, naming that minimum")
    func belowOwnPreset() throws {
        let floor = try #require(SetMinimumTipScreen.unmetMinimum(
            for: FiatAmount(value: 1, currency: .jmd),
            presets: jmdPresets,
            rate: jmdRate
        ))

        #expect(floor.displayed == FiatAmount(value: 150, currency: .jmd))
    }

    @Test("A fee at the preset minimum is accepted")
    func atOwnPreset() {
        #expect(SetMinimumTipScreen.unmetMinimum(
            for: FiatAmount(value: 150, currency: .jmd),
            presets: jmdPresets,
            rate: jmdRate
        ) == nil)
    }

    @Test("A currency without its own row is judged in USD against the fallback row")
    func belowUSDFallback() {
        // IDR 1 is a fraction of a cent; IDR 16000 is $1.
        #expect(SetMinimumTipScreen.unmetMinimum(
            for: FiatAmount(value: 1, currency: .idr),
            presets: usdPresets,
            rate: idrRate
        ) == .preset(usdPresets))
        #expect(SetMinimumTipScreen.unmetMinimum(
            for: FiatAmount(value: 16000, currency: .idr),
            presets: usdPresets,
            rate: idrRate
        ) == nil)
    }

    @Test("Without presets or a rate the server stays the authority")
    func noFloorWithoutPresetsOrRate() {
        let fee = FiatAmount(value: 1, currency: .jmd)

        #expect(SetMinimumTipScreen.unmetMinimum(for: fee, presets: nil, rate: jmdRate) == nil)
        #expect(SetMinimumTipScreen.unmetMinimum(for: fee, presets: usdPresets, rate: nil) == nil)
    }
}
