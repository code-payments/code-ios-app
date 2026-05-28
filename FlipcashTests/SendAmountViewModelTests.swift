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

    static func createViewModel(
        recipient: PublicKey = SendAmountViewModelTests.recipient,
        recipientDisplayName: String? = "Alice"
    ) -> SendAmountViewModel {
        SendAmountViewModel(
            sessionContainer: .mock,
            recipient: recipient,
            recipientDisplayName: recipientDisplayName,
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

    // MARK: - Recipient storage

    @Test("Init stores recipient pubkey and display name as provided")
    func init_storesRecipientFields() {
        let pubkey = PublicKey.generate()!
        let viewModel = Self.createViewModel(recipient: pubkey, recipientDisplayName: "Alice Anderson")
        #expect(viewModel.recipient == pubkey)
        #expect(viewModel.recipientDisplayName == "Alice Anderson")
    }

    @Test("Init keeps a nil display name (fallback handled at the view layer)")
    func init_keepsNilDisplayName() {
        let viewModel = Self.createViewModel(recipientDisplayName: nil)
        #expect(viewModel.recipientDisplayName == nil)
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
            recipient: .generate()!,
            recipientDisplayName: "Alice",
            mint: .generate()!  // unknown mint forces selectedBalance to nil
        )
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
            recipient: Self.recipient,
            recipientDisplayName: "Alice",
            mint: nil,
            sender: sender
        )
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
            recipient: Self.recipient,
            recipientDisplayName: "Alice",
            mint: nil,
            sender: sender
        )
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
            recipient: Self.recipient,
            recipientDisplayName: "Alice",
            mint: .usdf,
            sender: sender
        )
        viewModel.enteredAmount = "5"

        await viewModel.sendAction()

        // Pinned VerifiedState is absent in tests → rate-unavailable branch.
        #expect(sender.sendCalls.isEmpty)
        #expect(container.session.dialogItem != nil)
        #expect(viewModel.state == .ready)
    }
}
