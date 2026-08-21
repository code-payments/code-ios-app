//
//  ConvertConfirmationViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import SwiftUI
import FlipcashCore
import FlipcashUI
@testable import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("ConvertConfirmationViewModel")
struct ConvertConfirmationViewModelTests {

    // MARK: - Test Helpers -

    /// USD→CAD rate of 1.35 — native (CAD) is `usdValue * 1.35`, and
    /// `usdfValue` is derived back as `nativeAmount / 1.35`.
    static let testRate = Rate(fx: 1.35, currency: .cad)

    /// A bonded-mint amount, built directly to bypass the curve (pricing one
    /// through `compute` would need a supply that isn't what's under test).
    ///
    /// - Parameter onChainQuarks: raw token-native quarks (10 decimals).
    /// - Parameter nativeCAD: the CAD the amount is worth at ``testRate``.
    static func tokenAmount(onChainQuarks: UInt64, nativeCAD: Decimal) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: TokenAmount(quarks: onChainQuarks, mint: .jeffy),
            nativeAmount: FiatAmount(value: nativeCAD, currency: .cad),
            currencyRate: testRate
        )
    }

    /// A USDF amount. USDF bypasses the bonding curve, so `onChainAmount.quarks`
    /// is `usdfValue.value * 10^6`.
    static func dollarsAmount(onChainQuarks: UInt64 = 10_000_000_000) -> ExchangedFiat {
        ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: onChainQuarks, mint: .usdf),
            rate: testRate,
            supplyQuarks: nil
        )
    }

    /// Token → Dollars: the sell path. The pool's fee comes out of the amount.
    static func toDollars(
        amount: ExchangedFiat? = nil,
        sellFeeBps: Int? = 100,
        pinnedState: VerifiedState? = nil
    ) -> ConvertConfirmationViewModel {
        ConvertConfirmationViewModel(
            sourceMint: .jeffy,
            destinationMint: .usdf,
            destinationName: "Dollars",
            amount: amount ?? tokenAmount(onChainQuarks: 10_000_000_000, nativeCAD: 13_500),
            sellFeeBps: sellFeeBps,
            pinnedState: pinnedState ?? .fresh(bonded: false)
        )
    }

    /// Dollars → a token: a reserves buy. The flat 1% is added on top.
    static func fromDollars(
        amount: ExchangedFiat? = nil,
        pinnedState: VerifiedState? = nil
    ) -> ConvertConfirmationViewModel {
        ConvertConfirmationViewModel(
            sourceMint: .usdf,
            destinationMint: .jeffy,
            destinationName: "Jeffy",
            amount: amount ?? dollarsAmount(),
            sellFeeBps: nil,
            pinnedState: pinnedState ?? .fresh(bonded: false)
        )
    }

    // MARK: - Initialization -

    @Test("A fresh view model starts idle with nothing to dismiss")
    func initialization_defaultValues() {
        let viewModel = Self.toDollars()

        #expect(viewModel.actionButtonState == .normal)
        #expect(viewModel.dialogItem == nil)
        #expect(viewModel.canDismissSheet == false)
    }

    @Test("Direction flags follow the source and destination mints")
    func directionFlags() {
        #expect(Self.toDollars().isToDollars)
        #expect(!Self.toDollars().isFromDollars)
        #expect(Self.fromDollars().isFromDollars)
        #expect(!Self.fromDollars().isToDollars)
    }

    // MARK: - Fee -

    @Test("The fee is 1% of the on-chain amount")
    func fee_calculatesOnePercent() {
        // 10,000 whole tokens at 13,500 CAD. 1% → 100 tokens / 135 CAD.
        let viewModel = Self.toDollars(
            amount: Self.tokenAmount(onChainQuarks: 10_000_000_000, nativeCAD: 13_500)
        )

        let fee = viewModel.fee

        // Token-native math: 10_000_000_000 * 100 / 10_000 = 100_000_000 quarks
        #expect(fee.onChainAmount.quarks == 100_000_000)
        #expect(fee.nativeAmount.value == 135)
        // usdfValue is derived back through the rate: 135 / 1.35 = 100
        #expect(fee.usdfValue.value == 100)
    }

    @Test("A large amount's fee stays exact — no overflow in the split multiply")
    func fee_largeAmount_calculatesCorrectly() {
        let viewModel = Self.toDollars(
            amount: Self.tokenAmount(onChainQuarks: 1_000_000_000_000, nativeCAD: 1_350_000)
        )

        let fee = viewModel.fee

        #expect(fee.onChainAmount.quarks == 10_000_000_000)
        #expect(fee.nativeAmount.value == 13_500)
        #expect(fee.usdfValue.value == 10_000)
    }

    @Test("A fee below one quark rounds down to zero on both sides")
    func fee_smallAmount_roundsDown() {
        // 50 quarks * 100 / 10_000 = 0 (integer division rounds down)
        let viewModel = Self.toDollars(
            amount: Self.tokenAmount(onChainQuarks: 50, nativeCAD: Decimal(string: "0.0000000675")!)
        )

        let fee = viewModel.fee

        #expect(fee.onChainAmount.quarks == 0)
        #expect(fee.nativeAmount.value == 0)
    }

    @Test("The fee carries the amount's mint, currency, and rate")
    func fee_preservesCurrencyMetadata() {
        let amount = Self.tokenAmount(onChainQuarks: 10_000_000_000, nativeCAD: 13_500)
        let viewModel = Self.toDollars(amount: amount)

        let fee = viewModel.fee

        #expect(fee.nativeAmount.currency == amount.nativeAmount.currency)
        #expect(fee.currencyRate.currency == amount.currencyRate.currency)
        #expect(fee.mint == amount.mint)
    }

    @Test("The fee's native side scales by the exact on-chain ratio")
    func fee_scalesNativeProportionally() {
        // 5 whole Jeffy (10 decimals) at $13.50 CAD.
        let viewModel = Self.toDollars(
            amount: Self.tokenAmount(onChainQuarks: 50_000_000_000, nativeCAD: Decimal(string: "13.50")!)
        )

        let fee = viewModel.fee

        // 50_000_000_000 * 100 / 10_000 = 500_000_000 Jeffy quarks
        #expect(fee.onChainAmount.quarks == 500_000_000)
        #expect(fee.onChainAmount.mint == .jeffy)
        // Native scaled by 500M / 50B = 0.01 → 13.50 * 0.01 = 0.135 CAD
        #expect(fee.nativeAmount.value == Decimal(string: "0.135")!)
        #expect(fee.nativeAmount.currency == .cad)
    }

    @Test("The source pool's sell fee drives the rate, not a hardcoded 1%")
    func fee_usesSourceSellFeeBps() {
        let amount = Self.tokenAmount(onChainQuarks: 10_000_000_000, nativeCAD: 13_500)

        // 250 bps = 2.5%
        #expect(Self.toDollars(amount: amount, sellFeeBps: 250).fee.onChainAmount.quarks == 250_000_000)
        // A missing bps falls back to 1%.
        #expect(Self.toDollars(amount: amount, sellFeeBps: nil).fee.onChainAmount.quarks == 100_000_000)
        // A nonsensical negative bps clamps to no fee rather than trapping.
        #expect(Self.toDollars(amount: amount, sellFeeBps: -5).fee.onChainAmount.quarks == 0)
    }

    @Test("Converting from Dollars charges a flat 1% regardless of the destination pool")
    func fee_fromDollars_isFlatOnePercent() {
        // 10,000 USDF (6 decimals) → 100 USDF fee.
        let viewModel = Self.fromDollars(amount: Self.dollarsAmount(onChainQuarks: 10_000_000_000))

        let fee = viewModel.fee

        #expect(fee.onChainAmount.quarks == 100_000_000)
        #expect(fee.mint == .usdf)
    }

    // MARK: - Fee formatting -

    @Test("A fee of exactly zero formats without the tilde")
    func feeFormatted_zeroOnChainFee_dropsTildePrefix() {
        // 1% of 50 quarks rounds to 0 — the fee is literally zero, so $0.00,
        // not ~$0.00.
        let viewModel = Self.toDollars(
            amount: Self.tokenAmount(onChainQuarks: 50, nativeCAD: Decimal(string: "0.0000000675")!)
        )

        #expect(!viewModel.feeFormatted.contains("~"))
    }

    @Test("A non-zero but sub-cent fee keeps the tilde")
    func feeFormatted_nonZeroButSubCentFee_keepsTildePrefix() {
        // 1% of 100 quarks is 1 quark — non-zero, but far below CAD's display
        // precision. This is the "~$0.00" case.
        let viewModel = Self.toDollars(
            amount: Self.tokenAmount(onChainQuarks: 100, nativeCAD: Decimal(string: "0.000000135")!)
        )

        #expect(viewModel.feeFormatted.contains("~"))
    }

    // MARK: - Amount after fee / total debited -

    @Test("Converting to Dollars nets the amount minus the fee, and debits the amount")
    func amountAfterFee_toDollars_subtractsFee() {
        let amount = Self.tokenAmount(onChainQuarks: 10_000_000_000, nativeCAD: 13_500)
        let viewModel = Self.toDollars(amount: amount)

        // 10_000_000_000 - 100_000_000 = 9_900_000_000 quarks
        #expect(viewModel.amountAfterFee.onChainAmount.quarks == 9_900_000_000)
        #expect(viewModel.amountAfterFee.nativeAmount.value == 13_365)
        #expect(viewModel.amountAfterFee.usdfValue.value == 9_900)
        // The entered amount already is the debit — nothing is added on top.
        #expect(viewModel.totalDebited.onChainAmount.quarks == amount.onChainAmount.quarks)
    }

    @Test("Converting from Dollars receives the amount in full and debits amount + fee")
    func amountAfterFee_fromDollars_addsFeeOnTop() {
        let amount = Self.dollarsAmount(onChainQuarks: 10_000_000_000)
        let viewModel = Self.fromDollars(amount: amount)

        #expect(viewModel.amountAfterFee.onChainAmount.quarks == amount.onChainAmount.quarks,
                "the on-top fee must not shrink what the user receives")
        #expect(viewModel.totalDebited.onChainAmount.quarks == 10_100_000_000)
        #expect(viewModel.totalDebited == amount.adding(viewModel.fee))
    }

    @Test("The netted amount keeps the source mint")
    func amountAfterFee_preservesMint() {
        #expect(Self.toDollars().amountAfterFee.mint == .jeffy)
        #expect(Self.fromDollars().amountAfterFee.mint == .usdf)
    }

    @Test("A near-max amount's fee does not overflow")
    func fee_maxUInt64_doesNotOverflow() {
        // The split multiply in launchpadSellFee has to hold at 10-decimal
        // launchpad scale, where quarks × bps would overflow UInt64.
        let safeMax = UInt64.max / 100
        let viewModel = Self.toDollars(
            amount: Self.tokenAmount(onChainQuarks: safeMax, nativeCAD: 13_500)
        )

        #expect(viewModel.fee.onChainAmount.quarks == safeMax * 100 / 10_000)
    }

    // MARK: - Pinned state -

    @Test("canPerformAction is false when pinnedState is stale")
    func canPerformAction_stalePinnedState_returnsFalse() {
        #expect(Self.toDollars(pinnedState: .stale()).canPerformAction == false)
    }

    @Test("canPerformAction is true when pinnedState is fresh")
    func canPerformAction_freshPinnedState_returnsTrue() {
        #expect(Self.toDollars(pinnedState: .fresh()).canPerformAction == true)
    }

    // MARK: - Dialogs -

    @Test("A dialog set on the view model surfaces")
    func dialogItem_canBeSet() {
        let viewModel = Self.toDollars()

        viewModel.dialogItem = .success(title: "Test", subtitle: "Test subtitle")

        #expect(viewModel.dialogItem?.title == "Test")
    }
}
