//
//  SendAmountViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashUI
@testable import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("SendAmountViewModel")
struct SendAmountViewModelTests {

    // MARK: - Helpers

    private static let recipient: PublicKey = .generate()!

    static func makeContact(displayName: String = "Alice", dmChatID: Data? = nil) -> ResolvedContact {
        ResolvedContact(
            contactId: "test-contact",
            displayName: displayName,
            phoneE164: "+15551234567",
            nationalPhone: "(555) 123-4567",
            imageData: nil,
            dmChatID: dmChatID
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

    /// Funded USDF container with a pinned fresh USD verified state and send
    /// limits — everything `sendAction` needs to clear the pin and limit gates
    /// and reach an actual `sender.send`. (`makeFundedContainer` omits the pin
    /// so its tests exercise the rate-unavailable branch.)
    static func makeReadyToSendContainer(sendLimitUSD: Decimal = 1000) async throws -> SessionContainer {
        let limit = FiatAmount(value: sendLimitUSD, currency: .usd)
        let container = try SessionContainer.makeTest(
            holdings: [.init(mint: .usdf, quarks: 100_000_000)], // $100 USDF
            limits: Limits(
                sinceDate: .now,
                fetchDate: .now,
                sendLimits: [.usd: SendLimit(
                    nextTransaction: limit,
                    maxPerTransaction: limit,
                    maxPerDay: limit
                )]
            )
        )
        container.ratesController.configureTestRates(
            balanceCurrency: .usd,
            rates: [Rate(fx: 1.0, currency: .usd)]
        )
        await container.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "USD", rate: 1.0)
        ])
        return container
    }

    // MARK: - Init resolution

    @Test("Init with no mint and no prior selection skips USDF and auto-selects a giveable currency")
    func testInit_NoMint_NoSelection_SkipsUSDF() throws {
        // USDF holds the highest value, so the pre-fix resolver auto-selected it;
        // the giveable filter must skip it and land on the launchpad currency.
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: .usdf, quarks: 100_000_000_000), // $100k USDF — sorts first
            .init(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: 10_000 * 10_000_000_000),
                quarks: 1_000_000_000_000
            ),
        ])
        container.ratesController.selectedTokenMint = nil

        let viewModel = SendAmountViewModel(sessionContainer: container, contact: Self.makeContact(), mint: nil)

        #expect(viewModel.selectedBalance?.stored.mint == .jeffy)
        #expect(container.ratesController.selectedTokenMint == .jeffy)
    }

    @Test("Init with a stale USDF global selection still resolves to a giveable currency")
    func testInit_NoMint_StaleUSDFSelection_SkipsUSDF() throws {
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: .usdf, quarks: 100_000_000_000),
            .init(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: 10_000 * 10_000_000_000),
                quarks: 1_000_000_000_000
            ),
        ])
        container.ratesController.selectToken(.usdf)

        let viewModel = SendAmountViewModel(sessionContainer: container, contact: Self.makeContact(), mint: nil)

        #expect(viewModel.selectedBalance?.stored.mint == .jeffy)
        #expect(container.ratesController.selectedTokenMint == .jeffy)
    }

    // MARK: - canSend

    @Test("canSend is false when no amount is entered")
    func canSend_emptyAmount_isFalse() {
        let viewModel = Self.createViewModel()
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest())
        viewModel.enteredAmount = ""
        #expect(viewModel.canSend == false)
    }

    @Test("canSend is false when the entered amount can't parse as a positive decimal")
    func canSend_invalidAmount_isFalse() {
        let viewModel = Self.createViewModel()
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest())
        viewModel.enteredAmount = "not-a-number"
        #expect(viewModel.canSend == false)
    }

    @Test("canSend is false for a zero amount")
    func canSend_zero_isFalse() {
        let viewModel = Self.createViewModel()
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest())
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
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest())
        viewModel.enteredAmount = "5"
        // No resolve has happened — canSend reflects amount validity only, so a
        // red subtitle in EnterAmountView would mean over-limit, not unresolved.
        #expect(viewModel.canSend == true)
    }

    // MARK: - Locale amount parsing

    // Inputs are built with `Metrics.localizedDecimalSeparator`, exactly what the
    // keypad's decimal key inserts. On dot-decimal runners these pass trivially;
    // only on a comma-decimal runner (simulator/device region) can they catch a
    // parse that stops at the comma and drops the fraction.

    @Test("canSend accepts a sub-unit amount typed with the locale decimal separator")
    func canSend_localeSeparatorFraction_isTrue() {
        let viewModel = Self.createViewModel()
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest())
        viewModel.enteredAmount = "0\(Metrics.localizedDecimalSeparator)50"
        #expect(viewModel.canSend == true)
    }

    @Test("prepareSubmission keeps the fraction of an amount typed with the locale decimal separator")
    func prepareSubmission_localeSeparatorFraction_keepsFraction() async throws {
        let container = try await Self.makeReadyToSendContainer()
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf
        )
        viewModel.enteredAmount = "1\(Metrics.localizedDecimalSeparator)50"

        let submission = try #require(await viewModel.prepareSubmission())

        #expect(submission.amount.nativeAmount.value == Decimal(string: "1.5"))
    }

    // MARK: - selectCurrencyAction

    @Test("selectCurrencyAction syncs selectedBalance and ratesController")
    func selectCurrency_syncsBalanceAndRates() {
        let viewModel = Self.createViewModel()
        let balance = ExchangedBalance.makeTest(mint: .jeffy, quarks: 1_000_000_000_000, supplyQuarks: 10_000 * 10_000_000_000)
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        #expect(viewModel.selectedBalance?.stored.mint == .jeffy)
        #expect(viewModel.ratesController.selectedTokenMint == .jeffy)
    }

    @Test("selectCurrencyAction clears entered amount")
    func selectCurrency_clearsEnteredAmount() {
        let viewModel = Self.createViewModel()
        viewModel.enteredAmount = "42.00"
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest())
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
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest())
        viewModel.enteredAmount = ""

        let outcome = await viewModel.sendAction()

        #expect(outcome == .failed)
        #expect(sender.sendCalls.isEmpty)
        #expect(viewModel.session.dialogItem == nil)  // silent no-op: no dialog
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
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest(quarks: 0))
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .failed)
        // Sufficiency is checked first, so a short balance never hits the network.
        #expect(mock.resolveContactCalls.isEmpty)
        #expect(mock.sendCalls.isEmpty)
        let title = viewModel.session.dialogItem?.title
        #expect(title == "You Need More Cash" || title?.contains("Short") == true)
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
    }

    @Test("sendAction with a resolve network failure stays put, retries once, surfaces a dialog, does not send")
    func sendAction_resolveNetworkFailure_staysAndSkipsSend() async throws {
        let container = try Self.makeFundedContainer()
        let mock = MockSession()
        mock.resolveContactHandler = { _ in throw ErrorResolve.transportFailure }
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .failed)
        #expect(mock.resolveContactCalls.count == 2)  // initial attempt + one retry
        #expect(mock.sendCalls.isEmpty)
        #expect(container.session.dialogItem?.title == "Couldn't Send")
    }

    @Test("sendAction retries a transient resolve failure once, then sends successfully")
    func sendAction_resolveRetriesThenSucceeds_sends() async throws {
        let container = try await Self.makeReadyToSendContainer()
        let mock = MockSession()
        var attempts = 0
        mock.resolveContactHandler = { _ in
            attempts += 1
            if attempts == 1 { throw ErrorResolve.transportFailure }
            return Self.recipient
        }
        mock.sendHandler = { _, _, _ in }
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        // First resolve attempt throws networkError; the retry resolves and the
        // send completes end-to-end — proving the flow proceeds past the resolve.
        #expect(outcome == .success)
        #expect(mock.resolveContactCalls.count == 2)
        #expect(mock.sendCalls.count == 1)
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

        // The second call ran the full flow yet the resolve count stayed at 1 —
        // the cache, not an early bail, suppressed re-resolution.
        #expect(second == .failed)
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
        #expect(outcome == .failed)
        #expect(mock.sendCalls.isEmpty)
        #expect(container.session.dialogItem?.title == "Rate Unavailable")
    }

    @Test("sendAction with a pinned rate, funds, and a resolved recipient sends and returns .success")
    func sendAction_success_sendsAndReturnsSuccess() async throws {
        let container = try await Self.makeReadyToSendContainer()
        let mock = MockSession()
        mock.resolveContactHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }  // succeeds
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .success)
        #expect(mock.sendCalls.count == 1)
        #expect(mock.sendCalls.first?.destination == Self.recipient)
        #expect(container.session.dialogItem == nil)
    }

    @Test("sendAction attaches chat metadata when the contact has a DM chat and own phone is linked")
    func sendAction_withDmChatAndOwnPhone_attachesChatMetadata() async throws {
        let container = try await Self.makeReadyToSendContainer()
        let ownPhone = try #require(Phone("+14155550100"))
        container.session.profile = Profile(displayName: "Me", phone: ownPhone, email: nil)
        let mock = MockSession()
        mock.resolveContactHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }
        let dmChatID = Data(repeating: 0x07, count: 32)
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(dmChatID: dmChatID),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .success)
        let chat = try #require(mock.sendCalls.first?.chat)
        #expect(chat.chatID == ConversationID(data: dmChatID))
        #expect(chat.sourcePhoneE164 == ownPhone.e164)
        #expect(chat.destinationPhoneE164 == "+15551234567")
    }

    @Test("sendAction submits without chat metadata when the contact has no DM chat")
    func sendAction_withoutDmChat_sendsWithNilChat() async throws {
        let container = try await Self.makeReadyToSendContainer()
        let ownPhone = try #require(Phone("+14155550100"))
        container.session.profile = Profile(displayName: "Me", phone: ownPhone, email: nil)
        let mock = MockSession()
        mock.resolveContactHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .success)
        #expect(mock.sendCalls.count == 1)
        #expect(mock.sendCalls.first?.chat == nil)
    }

    @Test("sendAction returns .failed with a dialog when the send itself throws")
    func sendAction_sendThrows_returnsFailed() async throws {
        let container = try await Self.makeReadyToSendContainer()
        let mock = MockSession()
        mock.resolveContactHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in throw URLError(.timedOut) }
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .failed)
        #expect(mock.sendCalls.count == 1)  // the send was attempted
        #expect(container.session.dialogItem?.title == "Couldn't Send")
    }

    @Test("sendAction over the send limit returns .failed with the limit dialog and never sends")
    func sendAction_overSendLimit_returnsFailed() async throws {
        let container = try await Self.makeReadyToSendContainer(sendLimitUSD: 1)
        let mock = MockSession()
        mock.resolveContactHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            contact: Self.makeContact(),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"  // exceeds the $1 limit

        let outcome = await viewModel.sendAction()

        #expect(outcome == .failed)
        #expect(mock.sendCalls.isEmpty)  // the limit gate blocks before sending
        #expect(container.session.dialogItem?.title == "Transaction Limit Reached")
    }
}
