//
//  WalletDepositTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Wallet deposit landing")
struct WalletDepositTests {

    private static func fiat(_ value: Decimal) -> ExchangedFiat {
        ExchangedFiat(nativeAmount: FiatAmount(value: value, currency: .usd), rate: .oneToOne)
    }

    // MARK: - Arming

    @Test("arming records the wallet's figures and waits for the user")
    func arm_recordsLandingUnreleased() {
        let deposit = WalletDeposit()
        deposit.arm(mint: .usdf, previousTotal: Self.fiat(5), previousMints: [.usdf])

        #expect(deposit.landing?.previousTotal == Self.fiat(5))
        #expect(deposit.isReleased == false)
        #expect(deposit.releasedLanding == nil, "nothing plays until the user asks for the wallet")
    }

    @Test("a token the wallet has no card for is a new one")
    func isNewToken_forUnknownMint() {
        let deposit = WalletDeposit()
        deposit.arm(mint: .usdc, previousTotal: Self.fiat(5), previousMints: [.usdf])
        #expect(deposit.landing?.isNewToken == true)
    }

    @Test("a token already on the wallet is not a new one")
    func isNewToken_forHeldMint() {
        let deposit = WalletDeposit()
        deposit.arm(mint: .usdf, previousTotal: Self.fiat(5), previousMints: [.usdf, .usdc])
        #expect(deposit.landing?.isNewToken == false)
    }

    @Test("re-arming replaces an unplayed deposit and takes back its release")
    func arm_replacesPending() {
        let deposit = WalletDeposit()
        deposit.arm(mint: .usdf, previousTotal: Self.fiat(5), previousMints: [])
        deposit.release()

        deposit.arm(mint: .usdc, previousTotal: Self.fiat(9), previousMints: [.usdf])

        #expect(deposit.landing?.mint == .usdc)
        #expect(deposit.isReleased == false)
    }

    @Test("nothing is armed until a scanned grab arms it")
    func isArmed_onlyAfterArming() {
        let deposit = WalletDeposit()
        #expect(deposit.isArmed == false, "a cash link never arms one, so its receive takes the plain dismissal")

        deposit.arm(mint: .usdf, previousTotal: Self.fiat(5), previousMints: [])
        #expect(deposit.isArmed == true)

        deposit.release()
        deposit.consume()
        #expect(deposit.isArmed == false)
    }

    // MARK: - Release

    @Test("releasing hands the deposit to the wallet")
    func release_publishesLanding() {
        let deposit = WalletDeposit()
        deposit.arm(mint: .usdc, previousTotal: Self.fiat(5), previousMints: [.usdf])
        deposit.release()

        #expect(deposit.releasedLanding?.mint == .usdc)
    }

    @Test("releasing with nothing armed leaves the wallet alone")
    func release_withoutLanding_isNoop() {
        let deposit = WalletDeposit()
        deposit.release()

        #expect(deposit.isReleased == false)
        #expect(deposit.releasedLanding == nil)
    }

    // MARK: - Discard / consume

    @Test("a bill dismissed without asking for the wallet drops its deposit")
    func discard_dropsUnreleasedLanding() {
        let deposit = WalletDeposit()
        deposit.arm(mint: .usdc, previousTotal: Self.fiat(5), previousMints: [])
        deposit.discard()

        #expect(deposit.landing == nil)
    }

    @Test("the bill's own dismissal cannot drop a deposit the user just released")
    func discard_afterRelease_keepsLanding() {
        let deposit = WalletDeposit()
        deposit.arm(mint: .usdc, previousTotal: Self.fiat(5), previousMints: [])
        deposit.release()

        // What `dismissCashBill` runs as "Put in Wallet" takes the bill down.
        deposit.discard()

        #expect(deposit.releasedLanding?.mint == .usdc)
    }

    @Test("consuming clears the deposit once the wallet has played it")
    func consume_clearsLanding() {
        let deposit = WalletDeposit()
        deposit.arm(mint: .usdc, previousTotal: Self.fiat(5), previousMints: [])
        deposit.release()
        deposit.consume()

        #expect(deposit.landing == nil)
        #expect(deposit.isReleased == false)
        #expect(deposit.releasedLanding == nil)
    }
}

@MainActor
@Suite("Wallet card balances")
struct WalletCardBalancesTests {

    @Test("a token the user holds gets a card even when it is worth nothing yet")
    func keepsValuelessToken() {
        let balances = [WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdc, quarks: 0)]
        #expect(Session.walletCardBalances(from: balances).count == 1)
    }

    @Test("Dollars stay off the wallet until they are worth showing")
    func dropsEmptyDollars() {
        let balances = [WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf, quarks: 0)]
        #expect(Session.walletCardBalances(from: balances).isEmpty)
    }

    @Test("Dollars with a value get a card")
    func keepsFundedDollars() {
        let balances = [WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf, quarks: 10_000_000)]
        #expect(Session.walletCardBalances(from: balances).count == 1)
    }
}
