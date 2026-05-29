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

    /// Marks the recipient resolved by default so amount/send tests aren't
    /// gated by the background resolve. Pass `resolved: false` to exercise the
    /// resolving state.
    static func createViewModel(
        recipient: PublicKey = SendAmountViewModelTests.recipient,
        displayName: String = "Alice",
        resolved: Bool = true
    ) -> SendAmountViewModel {
        let viewModel = SendAmountViewModel(
            sessionContainer: .mock,
            contact: makeContact(displayName: displayName),
            mint: nil
        )
        if resolved { viewModel.recipientState = .resolved(recipient) }
        return viewModel
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

    // MARK: - Recipient

    @Test("Display name is taken from the contact")
    func init_exposesContactDisplayName() {
        let viewModel = Self.createViewModel(displayName: "Alice Anderson", resolved: false)
        #expect(viewModel.recipientDisplayName == "Alice Anderson")
    }

    @Test("Recipient starts in the resolving state")
    func init_startsResolving() {
        let viewModel = Self.createViewModel(resolved: false)
        #expect(viewModel.recipientState == .resolving)
    }

    // MARK: - canSend

    @Test("canSend is false while the recipient is still resolving")
    func canSend_whileResolving_isFalse() {
        let viewModel = Self.createViewModel(resolved: false)
        viewModel.selectCurrencyAction(exchangedBalance: Self.createExchangedBalance())
        viewModel.enteredAmount = "5"
        #expect(viewModel.canSend == false)
    }

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
        viewModel.recipientState = .resolved(Self.recipient)
        viewModel.enteredAmount = "10"
        #expect(viewModel.canSend == false)
    }

    @Test("canSend is true for a positive USDF amount with a selected balance")
    func canSend_positiveUSDF_isTrue() {
        let viewModel = Self.createViewModel()
        viewModel.selectCurrencyAction(exchangedBalance: Self.createExchangedBalance())
        viewModel.enteredAmount = "5"
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
        viewModel.recipientState = .resolved(Self.recipient)
        viewModel.selectCurrencyAction(exchangedBalance: Self.createExchangedBalance())
        viewModel.enteredAmount = ""

        await viewModel.sendAction()

        #expect(sender.sendCalls.isEmpty)
        #expect(viewModel.state == .ready)
    }

    @Test("sendAction with insufficient funds surfaces a dialog and does not call sender")
    func sendAction_insufficientFunds_setsDialogAndSkipsSender() async {
        let sender = MockSession()
        let viewModel = SendAmountViewModel(
            sessionContainer: .mock,
            contact: Self.makeContact(),
            mint: nil,
            sender: sender
        )
        viewModel.recipientState = .resolved(Self.recipient)
        // Empty balance + non-zero entered amount → hasSufficientFunds == .insufficient.
        viewModel.selectCurrencyAction(exchangedBalance: Self.createExchangedBalance(quarks: 0))
        viewModel.enteredAmount = "5"

        await viewModel.sendAction()

        #expect(sender.sendCalls.isEmpty)
        #expect(viewModel.session.dialogItem != nil)
    }

    @Test("sendAction surfaces a rate-unavailable dialog when no pinned VerifiedState is cached")
    func sendAction_noPinnedState_setsRateUnavailableDialog() async throws {
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: .usdf, quarks: 100_000_000), // $100 USDF
        ])
        container.ratesController.configureTestRates(rates: [.oneToOne])
        let sender = MockSession()
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: sender
        )
        viewModel.recipientState = .resolved(Self.recipient)
        viewModel.enteredAmount = "5"

        await viewModel.sendAction()

        // Pinned VerifiedState is absent in tests → rate-unavailable branch.
        #expect(sender.sendCalls.isEmpty)
        #expect(container.session.dialogItem != nil)
        #expect(viewModel.state == .ready)
    }
}
