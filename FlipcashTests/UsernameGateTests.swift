//
//  UsernameGateTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Username balance gate")
struct UsernameGateTests {

    /// Stands in for `Session`, which the gate only reads one property from.
    private final class StubBalances: UsernameBalanceReading {
        let totalBalance: ExchangedFiat

        init(usd: Decimal) {
            totalBalance = ExchangedFiat(
                nativeAmount: .usd(usd),
                rate: Rate(fx: 1, currency: .usd)
            )
        }

        /// Builds the total the way `Session.totalBalance` does: several
        /// balances, converted into the user's display currency and summed
        /// there. That round-trips through `rate.fx` in both directions, which
        /// the single-balance initialiser above never exercises.
        init(usd amounts: [Decimal], rate: Rate) {
            totalBalance = amounts
                .map { ExchangedFiat(nativeAmount: FiatAmount.usd($0).converting(to: rate), rate: rate) }
                .total(rate: rate)
        }
    }

    private func minimum(usd: Decimal) -> TokenAmount {
        TokenAmount(wholeTokens: usd, mint: .usdf)
    }

    @Test("A balance below the minimum is sent to Add Money, carrying the shortfall")
    func gate_belowMinimum_addMoney() {
        let gate = usernameGate(session: StubBalances(usd: 87.5), minimum: minimum(usd: 100))
        #expect(gate == .addMoney(minimum: .usd(100), shortfall: .usd(12.5), fraction: 0.875))
    }

    @Test("A balance exactly at the minimum proceeds")
    func gate_atMinimum_proceeds() {
        let gate = usernameGate(session: StubBalances(usd: 100), minimum: minimum(usd: 100))
        #expect(gate == .proceed)
        #expect(gate.fraction == 1)
    }

    @Test("A balance above the minimum proceeds")
    func gate_aboveMinimum_proceeds() {
        let gate = usernameGate(session: StubBalances(usd: 101), minimum: minimum(usd: 100))
        #expect(gate == .proceed)
    }

    @Test("A zero minimum lets everyone through, with a full bar rather than a division by zero")
    func gate_zeroMinimum_proceeds() {
        let gate = usernameGate(session: StubBalances(usd: 0), minimum: minimum(usd: 0))
        #expect(gate == .proceed)
        #expect(gate.fraction == 1)
    }

    @Test("Absent flags let everyone through rather than inventing a minimum, with a full bar")
    func gate_noFlags_proceeds() {
        let gate = usernameGate(session: StubBalances(usd: 0), minimum: nil)
        #expect(gate == .proceed)
        #expect(gate.fraction == 1)
    }

    @Test("A zero balance against a real minimum reports no progress rather than a negative one")
    func gate_zeroBalance_reportsNoProgress() {
        let gate = usernameGate(session: StubBalances(usd: 0), minimum: minimum(usd: 100))
        #expect(gate == .addMoney(minimum: .usd(100), shortfall: .usd(100), fraction: 0))
    }

    @Test("A partial balance reports its fraction of the minimum for the bar to size itself by")
    func gate_partialBalance_fractionMatchesRatio() {
        let gate = usernameGate(session: StubBalances(usd: 25), minimum: minimum(usd: 100))
        #expect(gate.fraction == 0.25)
    }

    @Test("A foreign-currency balance exactly at the minimum still proceeds")
    func gate_exactMinimumInForeignCurrency_proceeds() {
        // Three balances totalling exactly $100, held by someone whose display
        // currency isn't USD. Every balance reaching `totalBalance` is built as
        // `usd * fx`, so summing and dividing by `fx` inverts that exactly — no
        // amount or rate can make this drift today. The test pins that: it fails
        // the day someone rounds inside `converting`, `convertingToUSD` or
        // `total(rate:)`, which would cost this user a fraction of a cent and
        // deny them a username their balance screen says they qualify for.
        let session = StubBalances(usd: [40, 35, 25], rate: Rate(fx: 1.386523, currency: .cad))

        #expect(usernameGate(session: session, minimum: minimum(usd: 100)) == .proceed)
    }
}
