//
//  SendAmountViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite
struct SendAmountViewModelTests {

    // MARK: - Helpers

    private static let recipient: PublicKey = .generate()!

    static func makeContact(displayName: String = "Alice") -> ResolvedContact {
        ResolvedContact(
            contactId: "test-contact",
            displayName: displayName,
            phoneE164: "+15551234567",
            nationalPhone: "(555) 123-4567",
            imageData: nil
        )
    }

    /// View model over the `.mock` container, for amount/validation tests that
    /// never submit. `sendAction`-driven tests build their own funded container.
    static func createViewModel(displayName: String = "Alice") -> SendAmountViewModel {
        SendAmountViewModel(
            sessionContainer: .mock,
            contact: makeContact(displayName: displayName),
            mint: nil
        )
    }

    static func createExchangedBalance(
        mint: PublicKey = .usdf,
        quarks: UInt64 = 1_000_000,
        supplyQuarks: UInt64? = nil
    ) -> ExchangedBalance {
        let effectiveSupplyQuarks: UInt64?
        let effectiveSellFeeBps: Int?

        if mint == .usdf {
            effectiveSupplyQuarks = nil
            effectiveSellFeeBps = nil
        } else {
            effectiveSupplyQuarks = supplyQuarks ?? 10_000 * 10_000_000_000
            effectiveSellFeeBps = 0
        }

        let stored = try! StoredBalance(
            quarks: quarks,
            symbol: mint == .usdf ? "USDF" : "TOKEN",
            name: mint == .usdf ? "USDF Coin" : "Test Token",
            supplyFromBonding: effectiveSupplyQuarks,
            sellFeeBps: effectiveSellFeeBps,
            mint: mint,
            vmAuthority: mint == .usdf ? nil : .usdcAuthority,
            updatedAt: Date(),
            imageURL: nil,
            costBasis: 0
        )
        return ExchangedBalance(
            stored: stored,
            exchangedFiat: ExchangedFiat.compute(
                onChainAmount: TokenAmount(quarks: quarks, mint: mint),
                rate: .oneToOne,
                supplyQuarks: effectiveSupplyQuarks
            )
        )
    }

    /// Funded USDF container + test rates, mirroring the production amount-entry
    /// path so `sendAction` clears the local sufficiency gate and reaches the
    /// recipient resolve.
    static func makeFundedContainer() throws -> SessionContainer {
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: .usdf, quarks: 100_000_000), // $100 USDF
        ])
        container.ratesController.configureTestRates(rates: [.oneToOne])
        return container
    }

    // MARK: - Display

    @Test("Display name is taken from the contact")
    func init_exposesContactDisplayName() {
        let viewModel = Self.createViewModel(displayName: "Alice Anderson")
        #expect(viewModel.recipientDisplayName == "Alice Anderson")
    }

    // MARK: - canSend

    @Test("canSend is false when no amount is entered")
    func canSend_emptyAmount_isFalse() {
        let viewModel = Self.createViewModel()
        viewModel.selectCurrencyAction(exchangedBalance: Self.createExchangedBalance())
        viewModel.enteredAmount = ""
        #expect(viewModel.canSend == false)
    }

    @Test("canSend is false when the entered amount can't parse as a positive decimal")
    func canSend_invalidAmount_isFalse() {
        let viewModel = Self.createViewModel()
        viewModel.selectCurrencyAction(exchangedBalance: Self.createExchangedBalance())
        viewModel.enteredAmount = "not-a-number"
        #expect(viewModel.canSend == false)
    }

    @Test("canSend is false for a zero amount")
    func canSend_zero_isFalse() {
        let viewModel = Self.createViewModel()
        viewModel.selectCurrencyAction(exchangedBalance: Self.createExchangedBalance())
        viewModel.enteredAmount = "0"
        #expect(viewModel.canSend == false)
    }

    @Test("canSend is false when no balance is selected")
    func canSend_noSelectedBalance_isFalse() {
        let viewModel = SendAmountViewModel(
            sessionContainer: .mock,
            contact: Self.makeContact(),
            mint: .generate()!  // unknown mint forces selectedBalance to nil
        )
        viewModel.enteredAmount = "10"
        #expect(viewModel.canSend == false)
    }

    @Test("canSend is true for a positive amount, never gated on recipient resolution")
    func canSend_positiveAmount_isTrueWithoutResolution() {
        let viewModel = Self.createViewModel()
        viewModel.selectCurrencyAction(exchangedBalance: Self.createExchangedBalance())
        viewModel.enteredAmount = "5"
        // No resolve has happened — canSend reflects amount validity only, so a
        // red subtitle in EnterAmountView would mean over-limit, not unresolved.
        #expect(viewModel.canSend == true)
    }

    // MARK: - selectCurrencyAction

    @Test("selectCurrencyAction syncs selectedBalance and ratesController")
    func selectCurrency_syncsBalanceAndRates() {
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(mint: .jeffy, quarks: 1_000_000_000_000, supplyQuarks: 10_000 * 10_000_000_000)
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        #expect(viewModel.selectedBalance?.stored.mint == .jeffy)
        #expect(viewModel.ratesController.selectedTokenMint == .jeffy)
    }

    @Test("selectCurrencyAction clears entered amount")
    func selectCurrency_clearsEnteredAmount() {
        let viewModel = Self.createViewModel()
        viewModel.enteredAmount = "42.00"
        viewModel.selectCurrencyAction(exchangedBalance: Self.createExchangedBalance())
        #expect(viewModel.enteredAmount == "")
    }

    // MARK: - sendAction

    @Test("sendAction with empty amount is a no-op and does not call sender")
    func sendAction_emptyAmount_isNoOp() async {
        let sender = MockSession()
        let viewModel = SendAmountViewModel(
            sessionContainer: .mock,
            contact: Self.makeContact(),
            mint: nil,
            sender: sender
        )
        viewModel.selectCurrencyAction(exchangedBalance: Self.createExchangedBalance())
        viewModel.enteredAmount = ""

        let outcome = await viewModel.sendAction()

        #expect(outcome == .stay)
        #expect(sender.sendCalls.isEmpty)
        #expect(viewModel.state == .ready)
    }

    @Test("sendAction with insufficient funds surfaces a dialog and resolves nothing")
    func sendAction_insufficientFunds_skipsResolveAndSend() async {
        let mock = MockSession()
        let viewModel = SendAmountViewModel(
            sessionContainer: .mock,
            contact: Self.makeContact(),
            mint: nil,
            sender: mock,
            resolver: mock
        )
        // Empty balance + non-zero entered amount → hasSufficientFunds == .insufficient.
        viewModel.selectCurrencyAction(exchangedBalance: Self.createExchangedBalance(quarks: 0))
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .stay)
        // Sufficiency is checked first, so a short balance never hits the network.
        #expect(mock.resolveContactCalls.isEmpty)
        #expect(mock.sendCalls.isEmpty)
        #expect(viewModel.session.dialogItem != nil)
    }

    @Test("sendAction with a NOT_FOUND recipient returns .recipientNotFound, surfaces a dialog, does not send")
    func sendAction_recipientNotFound_popsAndSkipsSend() async throws {
        let container = try Self.makeFundedContainer()
        let mock = MockSession()
        mock.resolveContactHandler = { _ in throw ErrorResolve.notFound }
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .recipientNotFound)
        #expect(mock.sendCalls.isEmpty)
        #expect(container.session.dialogItem?.title == "Not on Flipcash")
        #expect(viewModel.state == .ready)
    }

    @Test("sendAction with a resolve network failure stays put, retries once, surfaces a dialog, does not send")
    func sendAction_resolveNetworkFailure_staysAndSkipsSend() async throws {
        let container = try Self.makeFundedContainer()
        let mock = MockSession()
        mock.resolveContactHandler = { _ in throw ErrorResolve.networkError }
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .stay)
        #expect(mock.resolveContactCalls.count == 2)  // initial attempt + one retry
        #expect(mock.sendCalls.isEmpty)
        #expect(container.session.dialogItem?.title == "Couldn't Send")
        #expect(viewModel.state == .ready)
    }

    @Test("sendAction retries a transient resolve failure once, then proceeds past the resolve")
    func sendAction_resolveRetriesThenSucceeds_proceedsPastResolve() async throws {
        let container = try Self.makeFundedContainer()
        let mock = MockSession()
        var attempts = 0
        mock.resolveContactHandler = { _ in
            attempts += 1
            if attempts == 1 { throw ErrorResolve.networkError }
            return Self.recipient
        }
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        // Resolved on the retry, then prepareSubmission finds no pinned state in
        // tests → the "Rate Unavailable" dialog (not "Couldn't Send") proves the
        // resolve cleared and the flow proceeded past it.
        #expect(outcome == .stay)
        #expect(mock.resolveContactCalls.count == 2)
        #expect(mock.sendCalls.isEmpty)
        #expect(container.session.dialogItem?.title == "Rate Unavailable")
        #expect(viewModel.state == .ready)
    }

    @Test("sendAction caches the resolved recipient so a retried send doesn't re-resolve")
    func sendAction_cachesResolvedRecipient() async throws {
        let container = try Self.makeFundedContainer()
        let mock = MockSession()
        mock.resolveContactHandler = { _ in Self.recipient }
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        await viewModel.sendAction()               // resolves (call #1), then rate-unavailable
        let second = await viewModel.sendAction()  // re-enters; reuses the cached recipient

        // The second call ran the full flow (re-entered past the .ready guard,
        // .stay outcome) yet the resolve count stayed at 1 — the cache, not an
        // early bail, suppressed re-resolution.
        #expect(second == .stay)
        #expect(viewModel.state == .ready)
        #expect(mock.resolveContactCalls.count == 1)
    }

    @Test("sendAction surfaces a rate-unavailable dialog when no pinned VerifiedState is cached")
    func sendAction_noPinnedState_setsRateUnavailableDialog() async throws {
        let container = try Self.makeFundedContainer()
        let mock = MockSession()
        mock.resolveContactHandler = { _ in Self.recipient }
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        // Pinned VerifiedState is absent in tests → rate-unavailable branch.
        #expect(outcome == .stay)
        #expect(mock.sendCalls.isEmpty)
        #expect(container.session.dialogItem?.title == "Rate Unavailable")
        #expect(viewModel.state == .ready)
    }
}
