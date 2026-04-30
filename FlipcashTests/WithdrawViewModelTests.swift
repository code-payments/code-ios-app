//
//  WithdrawViewModelTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-02-27.
//

import Foundation
import Testing
import FlipcashCore
@testable import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("WithdrawViewModel")
struct WithdrawViewModelTests {

    @Test("Non-USD rate computes correct on-chain amount from entered amount")
    func enteredFiat_cadRate() {
        let cadRate = Rate(fx: 1.4, currency: .cad)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(entryCurrency: .cad, rates: [cadRate])
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance())
        viewModel.enteredAmount = "7.00" // $7 CAD

        let fiat = viewModel.enteredFiat
        #expect(fiat?.currencyRate.currency == .cad)
        // $7 CAD / 1.4 = $5 USDF → 5_000_000 quarks (6 decimals)
        #expect(fiat?.onChainAmount.quarks == 5_000_000)
    }

    @Test("Subtracts fee from on-chain amount on every withdrawal")
    func withdrawableAmount_withFee() {
        // Fee comes from userFlags (500_000 quarks = $0.50)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(withdrawalFeeQuarks: 500_000)
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance())
        viewModel.enteredAmount = "5.00"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        // $5.00 - $0.50 = $4.50
        #expect(viewModel.withdrawableAmount?.onChainAmount.quarks == 4_500_000)
    }

    @Test("Regression: returns nil (no crash) when fee exceeds entered amount")
    func withdrawableAmount_feeExceedsEntered_returnsNil() {
        // Fee comes from userFlags (1_000_000 quarks = $1.00)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(withdrawalFeeQuarks: 1_000_000)
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance())
        viewModel.enteredAmount = "0.50"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        #expect(viewModel.withdrawableAmount == nil)
    }

    @Test("Regression: bonded-mint negative delta is a USD value, not a raw token count")
    func negativeWithdrawableAmount_bondedMint_isUSDDelta() throws {
        // Fee comes from userFlags (1_000_000 quarks = $1.00)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(withdrawalFeeQuarks: 1_000_000)
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createBondedBalance())
        viewModel.enteredAmount = "0.50"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        let delta = try #require(viewModel.negativeWithdrawableAmount)

        // Overflow above $1 USD means token count is leaking through as a fiat value.
        #expect(delta.currency == .usd)
        #expect(delta.value > 0)
        #expect(delta.value <= Decimal(1))
    }

    // MARK: - canProceedToAddress

    @Test("Over-balance bonded entry disables Next via canProceedToAddress")
    func canProceedToAddress_overBalanceBonded_isFalse() throws {
        let (viewModel, balance) = try makeBondedSetup()
        let balanceValue = balance.exchangedFiat.nativeAmount.value

        viewModel.enteredAmount = "\(balanceValue * 100)"

        // enteredFiat stays non-nil so EnterAmountView's isExceedingLimit can
        // flip the subtitle red.
        #expect(viewModel.enteredFiat != nil)
        #expect(viewModel.canProceedToAddress == false)
    }

    @Test("Below-fee entry disables Next for USDF kind")
    func canProceedToAddress_usdfBelowFee_isFalse() throws {
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(
            quarks: 100_000_000,
            withdrawalFeeQuarks: 500_000 // $0.50
        )
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "0.10"

        #expect(viewModel.canProceedToAddress == false)
    }

    @Test("Above-fee entry allows Next for USDF kind")
    func canProceedToAddress_usdfAboveFee_isTrue() throws {
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(
            quarks: 100_000_000,
            withdrawalFeeQuarks: 500_000
        )
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "5.00"

        #expect(viewModel.canProceedToAddress == true)
    }

    @Test("Below-fee entry disables Next for sameMint (bonded) kind")
    func canProceedToAddress_bondedBelowFee_isFalse() throws {
        let (viewModel, _) = try makeBondedSetup(withdrawalFeeQuarks: 500_000)
        viewModel.enteredAmount = "0.10" // below the $0.50 fee priced via curve

        #expect(viewModel.canProceedToAddress == false)
    }

    @Test("At-or-below balance leaves canProceedToAddress enabled")
    func canProceedToAddress_withinBalanceBonded_isTrue() throws {
        let (viewModel, balance) = try makeBondedSetup()
        let balanceValue = balance.exchangedFiat.nativeAmount.value

        viewModel.enteredAmount = "\(balanceValue / 10)"

        #expect(viewModel.canProceedToAddress == true)
    }

    // MARK: - canCompleteWithdrawal

    @Test("canCompleteWithdrawal blocks .token for usdfToUsdc kind",
          arguments: [(DestinationMetadata.Kind.owner, true),
                      (DestinationMetadata.Kind.token, false)])
    func canCompleteWithdrawal_usdfToUsdc_acceptsOnlyOwner(args: (kind: DestinationMetadata.Kind, expected: Bool)) throws {
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture()
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "5.00"
        viewModel.enteredAddress = "11111111111111111111111111111111"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata(
            kind: args.kind,
            isValid: true
        )

        #expect(viewModel.canCompleteWithdrawal == args.expected)
    }

    @Test("canCompleteWithdrawal accepts .owner and .token for sameMint kind",
          arguments: [DestinationMetadata.Kind.owner, .token])
    func canCompleteWithdrawal_sameMint_permissiveForValidKinds(kind: DestinationMetadata.Kind) throws {
        let (container, balance) = try WithdrawViewModelTestHelpers.makeUSDFFixture()
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.kind = .sameMint(balance)
        viewModel.enteredAmount = "5.00"
        viewModel.enteredAddress = "11111111111111111111111111111111"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata(kind: kind, isValid: true)

        #expect(viewModel.canCompleteWithdrawal == true)
    }

    @Test("canCompleteWithdrawal is false without a destination")
    func canCompleteWithdrawal_noDestination_returnsFalse() {
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance(quarks: 10_000_000))
        viewModel.enteredAmount = "5.00"

        #expect(viewModel.canCompleteWithdrawal == false)
    }

    @Test("canCompleteWithdrawal is true when all required fields are valid")
    func canCompleteWithdrawal_allValid_returnsTrue() throws {
        let (container, balance) = try WithdrawViewModelTestHelpers.makeUSDFFixture()
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.kind = .sameMint(balance)
        viewModel.enteredAmount = "5.00"
        viewModel.enteredAddress = "11111111111111111111111111111111"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        #expect(viewModel.canCompleteWithdrawal == true)
    }

    // MARK: - Helpers

    /// Builds a `WithdrawViewModel` backed by an in-memory session whose
    /// `session.balance(for:)` is populated, so `maxWithdrawLimit` returns a
    /// real cap rather than zero.
    private func makeBondedSetup(withdrawalFeeQuarks: UInt64 = 0) throws -> (WithdrawViewModel, ExchangedBalance) {
        let mint: PublicKey = .jeffy
        let container = try SessionContainer.makeTest(holdings: [
            .init(
                mint: .makeLaunchpad(
                    address: mint,
                    supplyFromBonding: 1_000_000 * 10_000_000_000
                ),
                quarks: 10 * 10_000_000_000
            ),
        ])
        if withdrawalFeeQuarks > 0 {
            container.session.userFlags = UserFlags(
                isRegistered: true,
                isStaff: false,
                onrampProviders: [],
                preferredOnrampProvider: .unknown,
                minBuildNumber: 0,
                billExchangeDataTimeout: nil,
                newCurrencyPurchaseAmount: .zero(mint: .usdf),
                newCurrencyFeeAmount: .zero(mint: .usdf),
                withdrawalFeeAmount: TokenAmount(quarks: withdrawalFeeQuarks, mint: .usdf)
            )
        }
        let stored = try #require(container.session.balance(for: mint))
        let rate = container.ratesController.rateForEntryCurrency()
        let balance = ExchangedBalance(
            stored: stored,
            exchangedFiat: stored.computeExchangedValue(with: rate)
        )
        let viewModel = WithdrawViewModel(
            container: .mock,
            sessionContainer: container
        )
        viewModel.kind = .sameMint(balance)
        return (viewModel, balance)
    }

    @Test("selectCurrency assigns .sameMint kind for non-USDF balance")
    func selectCurrency_bondedBalance_setsSameMintKind() {
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        let balance = WithdrawViewModelTestHelpers.createBondedBalance(mint: .jeffy)

        viewModel.selectCurrency(balance)

        #expect(viewModel.kind == .sameMint(balance))
    }

    @Test("selectCurrency assigns .usdfToUsdc kind for USDF balance")
    func selectCurrency_usdfBalance_setsUsdfToUsdcKind() {
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        let balance = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf)

        viewModel.selectCurrency(balance)

        #expect(viewModel.kind == .usdfToUsdc(balance))
    }

    @Test("Non-USD rate: subtracts fee in USD and recomputes native amount")
    func withdrawableAmount_withFeeAndCADRate() {
        let cadRate = Rate(fx: 1.4, currency: .cad)
        // Fee comes from userFlags (500_000 quarks = $0.50)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(
            entryCurrency: .cad,
            rates: [cadRate],
            withdrawalFeeQuarks: 500_000
        )
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance())
        viewModel.enteredAmount = "7.00" // $7 CAD = $5 USD
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        let result = viewModel.withdrawableAmount

        // $5 USD - $0.50 USD = $4.50 USD on-chain
        #expect(result?.onChainAmount.quarks == 4_500_000)
        // $4.50 USD * 1.4 = $6.30 CAD native
        #expect(result?.currencyRate.currency == .cad)
        #expect(result?.nativeAmount.value == Decimal(string: "6.30"))

        // Display fee: $7.00 CAD − $6.30 CAD = $0.70 CAD
        #expect(viewModel.displayFee?.value == Decimal(string: "0.70"))
    }

    @Test("selectCurrency pushes .intro substep for USDF balance")
    func selectCurrency_usdfBalance_pushesIntroSubstep() {
        var pushed: [WithdrawNavigationPath] = []
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.pushSubstep = { pushed.append($0) }

        let balance = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf)
        viewModel.selectCurrency(balance)

        #expect(pushed == [.intro])
    }

    @Test("selectCurrency pushes .enterAmount substep for non-USDF balance")
    func selectCurrency_bondedBalance_pushesEnterAmountSubstep() {
        var pushed: [WithdrawNavigationPath] = []
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.pushSubstep = { pushed.append($0) }

        let balance = WithdrawViewModelTestHelpers.createBondedBalance(mint: .jeffy)
        viewModel.selectCurrency(balance)

        #expect(pushed == [.enterAmount])
    }

    // MARK: - prepareSubmission pin-at-compute

    @Test("prepareSubmission (USDF→USDC) computes quarks from the PINNED rate, not the live cache")
    func prepareSubmission_usdfToUsdc_usesPinnedRate() async throws {
        // Pinned: 1 USD = 1.35 CAD. Live cache drifted to 1.37 after the pin was captured.
        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            entryCurrency: .cad,
            rates: [Rate(fx: 1.37, currency: .cad)]
        )
        await sessionContainer.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "CAD", rate: 1.35)
        ])

        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf, quarks: 100_000_000)
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: sessionContainer)
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "1"

        let submission = try #require(await viewModel.prepareSubmission())

        // $1 CAD / 1.35 × 10^6 = 740_741 USDF quarks (HALF_UP rounded).
        // The live path (1.37) would yield 729_927 — the bug surface.
        #expect(submission.amount.onChainAmount.quarks == 740_741)
        #expect(submission.amount.currencyRate.fx == Decimal(1.35))
        #expect(submission.pinnedState.exchangeRate == 1.35)
    }

    @Test("prepareSubmission (sameMint bonded) computes quarks from PINNED rate AND pinned supply")
    func prepareSubmission_sameMint_usesPinnedRateAndSupply() async throws {
        let pinnedSupply: UInt64 = 1_000_000 * 10_000_000_000
        let liveSupply: UInt64 = 1_500_000 * 10_000_000_000

        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            entryCurrency: .cad,
            rates: [Rate(fx: 1.37, currency: .cad)]
        )
        await sessionContainer.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "CAD", rate: 1.35)
        ])
        await sessionContainer.ratesController.verifiedProtoService.saveReserveStates([
            .freshReserve(mint: .jeffy, supplyFromBonding: pinnedSupply)
        ])

        let bonded = WithdrawViewModelTestHelpers.createBondedBalance(
            mint: .jeffy,
            supplyFromBonding: liveSupply
        )
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: sessionContainer)
        viewModel.kind = .sameMint(bonded)
        viewModel.enteredAmount = "1"

        let submission = try #require(await viewModel.prepareSubmission())

        // Submitted ExchangedFiat must carry the pinned rate, not the live cache.
        #expect(submission.amount.currencyRate.fx == Decimal(1.35))

        // VerifiedState carried into session.withdraw must be the pinned proof —
        // pinned supply, not the live balance's supply.
        #expect(submission.pinnedState.exchangeRate == 1.35)
        #expect(submission.pinnedState.supplyFromBonding == pinnedSupply)
    }
}

@MainActor
@Suite("WithdrawKind")
struct WithdrawKindTests {

    @Test("sameMint exposes source mint as both source and destination")
    func sameMint_destinationMintMatchesSource() {
        let balance = WithdrawViewModelTestHelpers.createBondedBalance(mint: .jeffy)
        let kind: WithdrawKind = .sameMint(balance)
        #expect(kind.sourceMint == .jeffy)
        #expect(kind.destinationMint == .jeffy)
    }

    @Test("usdfToUsdc routes USDF source to USDC destination")
    func usdfToUsdc_destinationMintIsUsdc() {
        let balance = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf)
        let kind: WithdrawKind = .usdfToUsdc(balance)
        #expect(kind.sourceMint == .usdf)
        #expect(kind.destinationMint == .usdc)
    }

    @Test("destinationCurrencyName uses balance name for sameMint, USDC for usdfToUsdc")
    func destinationCurrencyName() {
        let bonded = WithdrawViewModelTestHelpers.createBondedBalance(mint: .jeffy)
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf)
        #expect(WithdrawKind.sameMint(bonded).destinationCurrencyName == "Test Token")
        #expect(WithdrawKind.usdfToUsdc(usdf).destinationCurrencyName == "USDC")
    }

    @Test("acceptsTokenAccount: true for sameMint, false for usdfToUsdc")
    func acceptsTokenAccount() {
        let bonded = WithdrawViewModelTestHelpers.createBondedBalance()
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf)
        #expect(WithdrawKind.sameMint(bonded).acceptsTokenAccount == true)
        #expect(WithdrawKind.usdfToUsdc(usdf).acceptsTokenAccount == false)
    }

    @Test("showsIntroScreen: false for sameMint, true for usdfToUsdc")
    func showsIntroScreen() {
        let bonded = WithdrawViewModelTestHelpers.createBondedBalance()
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf)
        #expect(WithdrawKind.sameMint(bonded).showsIntroScreen == false)
        #expect(WithdrawKind.usdfToUsdc(usdf).showsIntroScreen == true)
    }

    @Test("showsAmountInTokenLine: true for sameMint, false for usdfToUsdc")
    func showsAmountInTokenLine() {
        let bonded = WithdrawViewModelTestHelpers.createBondedBalance()
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf)
        #expect(WithdrawKind.sameMint(bonded).showsAmountInTokenLine == true)
        #expect(WithdrawKind.usdfToUsdc(usdf).showsAmountInTokenLine == false)
    }
}

// MARK: - WithdrawViewModel summary helpers

@MainActor
@Suite("WithdrawViewModel summary helpers")
struct WithdrawViewModelSummaryHelpersTests {

    @Test("showsAmountInTokenLine: true for sameMint, false for usdfToUsdc (VM passthrough)")
    func showsAmountInTokenLine_passthrough() {
        let bonded = WithdrawViewModelTestHelpers.createBondedBalance()
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf)
        let vmBonded = WithdrawViewModelTestHelpers.createViewModel()
        vmBonded.kind = .sameMint(bonded)
        let vmUsdf = WithdrawViewModelTestHelpers.createViewModel()
        vmUsdf.kind = .usdfToUsdc(usdf)
        #expect(vmBonded.showsAmountInTokenLine == true)
        #expect(vmUsdf.showsAmountInTokenLine == false)
    }

    @Test("amountInTokenText: nil for usdfToUsdc")
    func amountInTokenText_usdfToUsdc_isNil() {
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf, quarks: 100_000_000)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "5.00"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        #expect(viewModel.amountInTokenText == nil)
    }

    @Test("amountInTokenText: matches the post-fee on-chain decimal-scaled value for sameMint")
    func amountInTokenText_sameMint_matchesPostFeeDecimalValue() throws {
        let bonded = WithdrawViewModelTestHelpers.createBondedBalance()
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.kind = .sameMint(bonded)
        viewModel.enteredAmount = "10.00"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        let amountText = try #require(viewModel.amountInTokenText)
        let withdrawable = try #require(viewModel.withdrawableAmount)
        #expect(amountText == withdrawable.onChainAmount.decimalValue.formatted())
    }

    @Test("youReceiveDisplayValue: USDF returns fiat-formatted string")
    func youReceiveDisplayValue_usdf_returnsFiat() throws {
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf, quarks: 100_000_000)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(withdrawalFeeQuarks: 500_000) // $0.50
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "50.00"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        let value = try #require(viewModel.youReceiveDisplayValue)
        // $50.00 - $0.50 fee = $49.50; the formatter typically yields "$49.50".
        #expect(value.contains("49.50"))
    }

    @Test("youReceiveDisplayValue: bonded returns on-chain quark count as numeric string")
    func youReceiveDisplayValue_bonded_returnsTokenCount() throws {
        let bonded = WithdrawViewModelTestHelpers.createBondedBalance()
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.kind = .sameMint(bonded)
        viewModel.enteredAmount = "10.00"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        let value = try #require(viewModel.youReceiveDisplayValue)
        // Bonded path renders the same quark count as amountInTokenText —
        // same number, different framing on screen.
        #expect(value == viewModel.amountInTokenText)
    }

    @Test("destinationLogoURL: usdfToUsdc returns MintMetadata.usdc.imageURL")
    func destinationLogoURL_usdfToUsdc_matchesUSDCMetadata() {
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.kind = .usdfToUsdc(usdf)

        #expect(viewModel.destinationLogoURL == MintMetadata.usdc.imageURL)
    }

    @Test("destinationLogoURL: sameMint returns the source balance's imageURL")
    func destinationLogoURL_sameMint_matchesBalanceImageURL() {
        let bonded = WithdrawViewModelTestHelpers.createBondedBalance()
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.kind = .sameMint(bonded)

        #expect(viewModel.destinationLogoURL == bonded.stored.imageURL)
    }

    @Test("amountSubtitle returns balanceWithLimit when within bounds")
    func amountSubtitle_withinBounds_returnsBalanceWithLimit() {
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf, quarks: 100_000_000)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "5.00"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        switch viewModel.amountSubtitle {
        case .balanceWithLimit:
            break
        case .singleTransactionLimit, .custom:
            Issue.record("Expected .balanceWithLimit subtitle for valid amount")
        }
    }

    @Test("amountSubtitle returns custom 'Enter more than' when entered amount is at or below the fee")
    func amountSubtitle_belowFee_returnsCustomCopy() {
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf, quarks: 100_000_000)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(withdrawalFeeQuarks: 500_000) // $0.50
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "0.10"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        switch viewModel.amountSubtitle {
        case .custom(let copy):
            #expect(copy.contains("Enter more than"))
            #expect(copy.contains("0.50"))
        case .balanceWithLimit, .singleTransactionLimit:
            Issue.record("Expected .custom subtitle for amount below fee")
        }
    }
}
