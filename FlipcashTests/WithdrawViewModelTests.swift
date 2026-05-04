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
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(balanceCurrency: .cad, rates: [cadRate])
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

    @Test("Bonded mint below the fee gates the amount-entry screen")
    func isBelowMinimumWithdraw_bondedMint_belowFee_isTrue() throws {
        // Fee comes from userFlags (1_000_000 quarks = $1.00)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(withdrawalFeeQuarks: 1_000_000)
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createBondedBalance())
        viewModel.enteredAmount = "0.50"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        #expect(viewModel.isBelowMinimumWithdraw == true)
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

    @Test("Below-fee entry keeps Next enabled for USDF kind so the dialog can fire")
    func canProceedToAddress_usdfBelowFee_isTrue() throws {
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(
            quarks: 100_000_000,
            withdrawalFeeQuarks: 500_000 // $0.50
        )
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "0.10"

        #expect(viewModel.canProceedToAddress == true)
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

    @Test("Below-fee entry keeps Next enabled for sameMint (bonded) kind")
    func canProceedToAddress_bondedBelowFee_isTrue() throws {
        let (viewModel, _) = try makeBondedSetup(withdrawalFeeQuarks: 500_000)
        viewModel.enteredAmount = "0.10" // below the $0.50 fee priced via curve

        #expect(viewModel.canProceedToAddress == true)
    }

    // MARK: - amountEnteredAction below-fee gate

    @Test("amountEnteredAction below the fee surfaces the too-small dialog instead of advancing")
    func amountEnteredAction_belowFee_showsTooSmallDialog() throws {
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(
            quarks: 100_000_000,
            withdrawalFeeQuarks: 500_000 // $0.50
        )
        var pushed: [WithdrawNavigationPath] = []
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.pushSubstep = { pushed.append($0) }
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "0.10"

        viewModel.amountEnteredAction()

        #expect(viewModel.dialogItem?.title == "Withdrawal Amount Too Small")
        #expect(pushed.isEmpty)
    }

    @Test("amountEnteredAction at-or-above fee pushes the address screen")
    func amountEnteredAction_aboveFee_pushesAddressScreen() throws {
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(
            quarks: 100_000_000,
            withdrawalFeeQuarks: 500_000
        )
        var pushed: [WithdrawNavigationPath] = []
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.pushSubstep = { pushed.append($0) }
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "5.00"

        viewModel.amountEnteredAction()

        #expect(viewModel.dialogItem == nil)
        #expect(pushed == [.enterAddress])
    }

    // MARK: - minimumWithdrawAmount

    @Test("minimumWithdrawAmount: USD = fee + $0.01")
    func minimumWithdrawAmount_USD_returnsFeePlusOneCent() throws {
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(
            quarks: 100_000_000,
            withdrawalFeeQuarks: 500_000 // $0.50
        )
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "0.10"

        let minimum = try #require(viewModel.minimumWithdrawAmount)
        #expect(minimum.currency == .usd)
        #expect(minimum.value == Decimal(string: "0.51"))
    }

    @Test("minimumWithdrawAmount: JPY 158.6 → displayed fee ¥79 + ¥1 = ¥80")
    func minimumWithdrawAmount_JPY_158_6() {
        let jpyRate = Rate(fx: 158.6, currency: .jpy)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(
            balanceCurrency: .jpy,
            rates: [jpyRate],
            withdrawalFeeQuarks: 500_000 // $0.50
        )
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance())
        viewModel.enteredAmount = "10"

        // 0.50 × 158.6 = 79.3 → half-up to 0dp = ¥79; + ¥1 = ¥80
        #expect(viewModel.minimumWithdrawAmount?.currency == .jpy)
        #expect(viewModel.minimumWithdrawAmount?.value == Decimal(80))
    }

    @Test("minimumWithdrawAmount: JPY 159.4 → displayed fee ¥80 + ¥1 = ¥81")
    func minimumWithdrawAmount_JPY_159_4_displayedFeeRoundsUp() {
        let jpyRate = Rate(fx: 159.4, currency: .jpy)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(
            balanceCurrency: .jpy,
            rates: [jpyRate],
            withdrawalFeeQuarks: 500_000
        )
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance())
        viewModel.enteredAmount = "10"

        // 0.50 × 159.4 = 79.7 → half-up to 0dp = ¥80; + ¥1 = ¥81
        #expect(viewModel.minimumWithdrawAmount?.value == Decimal(81))
    }

    @Test("isBelowMinimumWithdraw: entering exactly the displayed minimum passes (CAD)")
    func isBelowMinimumWithdraw_CAD_displayedMinimumPasses() {
        // Rate 1.36 → fee in CAD = 0.68 → minimum = $0.69. Entering "$0.69"
        // (keypad emits "0.69" with a "." separator regardless of device locale)
        // must not fire the gate, even when the device locale uses ",".
        let cadRate = Rate(fx: 1.36, currency: .cad)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(
            balanceCurrency: .cad,
            rates: [cadRate],
            withdrawalFeeQuarks: 500_000 // $0.50
        )
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance())

        viewModel.enteredAmount = "0.68"
        #expect(viewModel.isBelowMinimumWithdraw == true)

        viewModel.enteredAmount = "0.69"
        #expect(viewModel.isBelowMinimumWithdraw == false)
    }

    @Test("isBelowMinimumWithdraw: blocks amounts where displayed net would be ¥0")
    func isBelowMinimumWithdraw_JPY_blocksZeroNet() {
        // Rate 157 → displayed fee ¥79 (0.5 × 157 = 78.5, half-up to ¥79).
        // ¥79 entered yields displayed net ¥0 (entered − fee = ¥79 − ¥79 = ¥0)
        // — useless, so the gate must block it.
        let jpyRate = Rate(fx: 157, currency: .jpy)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(
            balanceCurrency: .jpy,
            rates: [jpyRate],
            withdrawalFeeQuarks: 500_000
        )
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance())

        viewModel.enteredAmount = "79"
        #expect(viewModel.isBelowMinimumWithdraw == true)

        viewModel.enteredAmount = "80"
        #expect(viewModel.isBelowMinimumWithdraw == false)
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

    @Test("canCompleteWithdrawal accepts every kind for sameMint when isValid=true",
          arguments: [DestinationMetadata.Kind.owner, .token, .unknown])
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
        let rate = container.ratesController.rateForBalanceCurrency()
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
            balanceCurrency: .cad,
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
            balanceCurrency: .cad,
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
            balanceCurrency: .cad,
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

}

// MARK: - WithdrawViewModel summary helpers

@MainActor
@Suite("WithdrawViewModel summary helpers")
struct WithdrawViewModelSummaryHelpersTests {

    @Test("youReceiveDisplayValue: USDF returns post-fee on-chain token amount")
    func youReceiveDisplayValue_usdf_returnsTokenAmount() throws {
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf, quarks: 100_000_000)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(withdrawalFeeQuarks: 500_000) // $0.50
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "50.00"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        let value = try #require(viewModel.youReceiveDisplayValue)
        let withdrawable = try #require(viewModel.withdrawableAmount)
        #expect(value == withdrawable.onChainAmount.decimalValue.formatted())
    }

    /// Regression: WithdrawSummaryScreen wraps the entire amount/fee/net/You-Receive
    /// card in `if let entered, let net, let display`. When any one of those goes
    /// nil the user sees a near-empty screen with just the address and Withdraw
    /// button. Locks the three values together for the USDF→USDC flow with and
    /// without destination metadata, so any future regression to the underlying
    /// computations fails here instead of silently hiding the card.
    @Test("summary card values are all non-nil for usdfToUsdc at 1 CAD")
    func summaryCard_usdfToUsdc_oneCAD_allValuesNonNil() {
        let viewModel = makeUsdfToUsdcCadViewModel()
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        #expect(viewModel.enteredFiat != nil)
        #expect(viewModel.displayNet != nil)
        #expect(viewModel.youReceiveDisplayValue != nil)
    }

    /// Regression: youReceiveDisplayValue and withdrawableAmount must NOT depend on
    /// destinationMetadata. They feed the summary card; if they vanish whenever
    /// metadata is briefly nil (initial render before async fetch settles, stale
    /// state on re-entry, server-failed validation), the user sees a half-blank
    /// summary. The fee-subtracted token amount is purely a function of the
    /// entered amount and the static fee — keep it that way.
    @Test("youReceiveDisplayValue does not depend on destinationMetadata")
    func youReceiveDisplayValue_noMetadata_stillRenders() {
        let viewModel = makeUsdfToUsdcCadViewModel()

        #expect(viewModel.destinationMetadata == nil)
        #expect(viewModel.withdrawableAmount != nil)
        #expect(viewModel.youReceiveDisplayValue != nil)
    }

    private func makeUsdfToUsdcCadViewModel() -> WithdrawViewModel {
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf, quarks: 100_000_000)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(
            balanceCurrency: .cad,
            rates: [Rate(fx: 1.4, currency: .cad)],
            withdrawalFeeQuarks: 500_000 // $0.50
        )
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "1"
        return viewModel
    }

    @Test("youReceiveDisplayValue: bonded returns post-fee on-chain token amount")
    func youReceiveDisplayValue_bonded_returnsTokenCount() throws {
        let bonded = WithdrawViewModelTestHelpers.createBondedBalance()
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.kind = .sameMint(bonded)
        viewModel.enteredAmount = "10.00"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        let value = try #require(viewModel.youReceiveDisplayValue)
        let withdrawable = try #require(viewModel.withdrawableAmount)
        #expect(value == withdrawable.onChainAmount.decimalValue.formatted())
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
        case .singleTransactionLimit, .error:
            Issue.record("Expected .balanceWithLimit subtitle for valid amount")
        }
    }

    @Test("amountSubtitle returns 'Minimum withdrawal' error copy when entered amount is at or below the fee")
    func amountSubtitle_belowFee_returnsMinimumWithdrawalErrorCopy() {
        let usdf = WithdrawViewModelTestHelpers.createExchangedBalance(mint: .usdf, quarks: 100_000_000)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(withdrawalFeeQuarks: 500_000) // $0.50
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "0.10"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        switch viewModel.amountSubtitle {
        case .error(let copy):
            #expect(copy.contains("Minimum withdrawal"))
            #expect(copy.contains("0.51"))
        case .balanceWithLimit, .singleTransactionLimit:
            Issue.record("Expected .error subtitle for amount below fee")
        }
    }
}
