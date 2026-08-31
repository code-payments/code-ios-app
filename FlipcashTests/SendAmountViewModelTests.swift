//
//  SendAmountViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
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
            target: .contact(makeContact(displayName: displayName)),
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

    @Test("Init with no mint and no prior selection prefers a community currency over USDF")
    func testInit_NoMint_NoSelection_SkipsUSDF() throws {
        // USDF is sendable, but it holds the highest value on nearly every
        // account — auto-picking it would open every send in Dollars, so the
        // resolver prefers the launchpad currency and keeps Dollars as a fallback.
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: .usdf, quarks: 100_000_000_000), // $100k USDF — sorts first
            .init(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: 10_000 * 10_000_000_000),
                quarks: 1_000_000_000_000
            ),
        ])
        container.ratesController.selectedTokenMint = nil

        let viewModel = SendAmountViewModel(sessionContainer: container, target: .contact(Self.makeContact()), mint: nil)

        #expect(viewModel.selectedBalance?.stored.mint == .jeffy)
        #expect(container.ratesController.selectedTokenMint == .jeffy)
    }

    @Test("Init with a stale USDF global selection still resolves to a community currency")
    func testInit_NoMint_StaleUSDFSelection_SkipsUSDF() throws {
        // `ensureValidTokenSelection` parks the global selection on the highest
        // balance, which is routinely USDF — that isn't an intentional Dollars pick.
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: .usdf, quarks: 100_000_000_000),
            .init(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: 10_000 * 10_000_000_000),
                quarks: 1_000_000_000_000
            ),
        ])
        container.ratesController.selectToken(.usdf)

        let viewModel = SendAmountViewModel(sessionContainer: container, target: .contact(Self.makeContact()), mint: nil)

        #expect(viewModel.selectedBalance?.stored.mint == .jeffy)
        #expect(container.ratesController.selectedTokenMint == .jeffy)
    }

    @Test("A view model built before balances load resolves once they arrive")
    func testInit_NoBalancesYet_ResolvesWhenBalancesArrive() async throws {
        // A tip deep link builds the view model at the coldest point of a cold
        // launch, before the balance list has loaded. The initial resolve comes
        // up empty; without a re-resolve that nil sticks for the life of the
        // flow — an empty token pill and a swipe that fails the `submit` guard.
        let container = try SessionContainer.makeTest(holdings: [])
        container.ratesController.configureTestRates(rates: [.oneToOne])
        container.ratesController.selectedTokenMint = nil

        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            target: .tip(TipRecipient(userID: UUID(), displayName: "Fred", origin: .tipcard)),
            mint: nil
        )
        #expect(viewModel.selectedBalance == nil)

        let mint = MintMetadata.makeLaunchpad(
            address: .jeffy,
            supplyFromBonding: 10_000 * 10_000_000_000
        )
        let now = Date.now
        try container.database.insert(mints: [mint], date: now)
        try container.database.transaction { db in
            try db.insertBalance(quarks: 1_000_000_000_000, mint: mint.address, costBasis: 0, date: now)
        }
        NotificationCenter.default.post(name: .databaseDidChange, object: nil)

        try await waitUntil(viewModel) { $0.selectedBalance?.stored.mint == .jeffy }
        #expect(container.ratesController.selectedTokenMint == .jeffy)
    }

    @Test("An explicit currency pick is not overwritten when balances later arrive")
    func testInit_ExplicitPick_SurvivesLateBalanceArrival() async throws {
        let container = try SessionContainer.makeTest(holdings: [])
        container.ratesController.configureTestRates(rates: [.oneToOne])

        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            target: .contact(Self.makeContact()),
            mint: nil
        )
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest())

        let mint = MintMetadata.makeLaunchpad(
            address: .jeffy,
            supplyFromBonding: 10_000 * 10_000_000_000
        )
        let now = Date.now
        try container.database.insert(mints: [mint], date: now)
        try container.database.transaction { db in
            try db.insertBalance(quarks: 1_000_000_000_000, mint: mint.address, costBasis: 0, date: now)
        }
        NotificationCenter.default.post(name: .databaseDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.selectedBalance?.stored.mint == .usdf)
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
            target: .contact(Self.makeContact()),
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

    // Inputs are built with `AmountValidator.localizedDecimalSeparator`, exactly what the
    // keypad's decimal key inserts. On dot-decimal runners these pass trivially;
    // only on a comma-decimal runner (simulator/device region) can they catch a
    // parse that stops at the comma and drops the fraction.

    @Test("canSend accepts a sub-unit amount typed with the locale decimal separator")
    func canSend_localeSeparatorFraction_isTrue() {
        let viewModel = Self.createViewModel()
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest())
        viewModel.enteredAmount = "0\(AmountValidator.localizedDecimalSeparator)50"
        #expect(viewModel.canSend == true)
    }

    @Test("prepareSubmission keeps the fraction of an amount typed with the locale decimal separator")
    func prepareSubmission_localeSeparatorFraction_keepsFraction() async throws {
        let container = try await Self.makeReadyToSendContainer()
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            target: .contact(Self.makeContact()),
            mint: .usdf
        )
        viewModel.enteredAmount = "1\(AmountValidator.localizedDecimalSeparator)50"

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
            target: .contact(Self.makeContact()),
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
            target: .contact(Self.makeContact()),
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
            target: .contact(Self.makeContact()),
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
            target: .contact(Self.makeContact()),
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
            target: .contact(Self.makeContact()),
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
            target: .contact(Self.makeContact()),
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
            target: .contact(Self.makeContact()),
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
            target: .contact(Self.makeContact()),
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
            target: .contact(Self.makeContact(dmChatID: dmChatID)),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .success)
        let chat = try #require(mock.sendCalls.first?.chat)
        guard case .contactDm(let chatID, let source, let destination) = chat else {
            Issue.record("Expected contactDm metadata, got \(chat)")
            return
        }
        #expect(chatID == ConversationID(data: dmChatID))
        #expect(source == ownPhone.e164)
        #expect(destination == "+15551234567")
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
            target: .contact(Self.makeContact()),
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
            target: .contact(Self.makeContact()),
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
            target: .contact(Self.makeContact()),
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

    @Test("A submission with no resolved balance surfaces a dialog instead of failing silently")
    func submit_noSelectedBalance_surfacesDialog() async throws {
        // The swipe control swallows a `.failed` outcome and just resets its
        // knob, so this branch has to report and dialog for itself.
        let container = try SessionContainer.makeTest(holdings: [])
        container.ratesController.configureTestRates(rates: [.oneToOne])
        let mock = MockSession()
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            target: .tip(TipRecipient(userID: UUID(), displayName: "Fred", origin: .tipcard)),
            mint: nil,
            sender: mock,
            resolver: mock
        )
        #expect(viewModel.selectedBalance == nil)

        let outcome = await viewModel.submit(entered: 5)

        #expect(outcome == .failed)
        #expect(mock.sendCalls.isEmpty)
        #expect(mock.resolveUserIDCalls.isEmpty)
        #expect(container.session.dialogItem?.title == "Balance Unavailable")
    }

    // MARK: - Tip targets

    @Test("A tip send resolves by user id and attaches the derived tip-DM chat metadata")
    func sendAction_tipTarget_attachesTipDmMetadata() async throws {
        let container = try await Self.makeReadyToSendContainer()
        let recipientID = UUID()
        let mock = MockSession()
        mock.resolveUserIDHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }
        let viewModel = Self.makeTipViewModel(container: container, recipientID: recipientID, origin: .tipcard, mock: mock)
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .success)
        #expect(mock.resolveUserIDCalls == [recipientID])
        #expect(mock.resolveContactCalls.isEmpty)
        let chat = try #require(mock.sendCalls.first?.chat)
        guard case .tipDm(let chatID, let origin) = chat else {
            Issue.record("Expected tipDm metadata, got \(chat)")
            return
        }
        #expect(chatID == ConversationID.tipDm(between: container.session.userID, and: recipientID))
        #expect(origin == .tipcard)
    }

    @Test("The tip that opens the DM reports as tipcard even when it's composed in a chat")
    func sendAction_tipOpeningDMFromChat_reportsTipcard() async throws {
        let container = try await Self.makeReadyToSendContainer()
        let recipientID = UUID()
        let mock = MockSession()
        mock.resolveUserIDHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }
        // What the username lookup pushes: a tip DM screen for someone the feed
        // holds no conversation for, so its Send Cash target says `.chat`.
        let viewModel = Self.makeTipViewModel(container: container, recipientID: recipientID, origin: .chat, mock: mock)
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .success)
        let chat = try #require(mock.sendCalls.first?.chat)
        guard case .tipDm(_, let origin) = chat else {
            Issue.record("Expected tipDm metadata, got \(chat)")
            return
        }
        // `CHAT` here is what the server rejects with "tip dm has not been
        // initialized" — there is no thread yet for this payment to be sent from.
        #expect(origin == .tipcard)
    }

    @Test("Once the DM exists, an in-chat send still reports as chat")
    func sendAction_tipExistingDMFromChat_reportsChat() async throws {
        let container = try await Self.makeReadyToSendContainer()
        let recipientID = UUID()
        try await Self.seedTipDM(in: container, with: recipientID)
        let mock = MockSession()
        mock.resolveUserIDHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }
        let viewModel = Self.makeTipViewModel(container: container, recipientID: recipientID, origin: .chat, mock: mock)
        viewModel.enteredAmount = "5"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .success)
        let chat = try #require(mock.sendCalls.first?.chat)
        guard case .tipDm(_, let origin) = chat else {
            Issue.record("Expected tipDm metadata, got \(chat)")
            return
        }
        #expect(origin == .chat)
    }

    @Test("A tip below the server minimum is blocked before submission")
    func sendAction_tipTarget_belowMinimumBlocks() async throws {
        let container = try await Self.makeReadyToSendContainer()
        container.session.userFlags = .fixture(tipPresets: [
            UserFlags.TipPresets(currency: .usd, minimum: 1, low: 5, medium: 10, high: 20),
        ])
        let recipientID = UUID()
        let mock = MockSession()
        mock.resolveUserIDHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }
        let viewModel = Self.makeTipViewModel(container: container, recipientID: recipientID, origin: .tipcard, mock: mock)
        viewModel.enteredAmount = "0\(AmountValidator.localizedDecimalSeparator)50"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .failed)
        #expect(mock.sendCalls.isEmpty)
        #expect(container.session.dialogItem?.title == "$1.00 Minimum Tip")
    }

    @Test("A tip at exactly the displayed minimum is allowed")
    func sendAction_tipTarget_atMinimumSends() async throws {
        let container = try await Self.makeReadyToSendContainer()
        container.session.userFlags = .fixture(tipPresets: [
            UserFlags.TipPresets(currency: .usd, minimum: 1, low: 5, medium: 10, high: 20),
        ])
        let recipientID = UUID()
        let mock = MockSession()
        mock.resolveUserIDHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }
        let viewModel = Self.makeTipViewModel(container: container, recipientID: recipientID, origin: .tipcard, mock: mock)
        viewModel.enteredAmount = "1"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .success)
        #expect(mock.sendCalls.count == 1)
    }

    @Test("A contact send never consults the tip minimum")
    func sendAction_contactTarget_ignoresTipMinimum() async throws {
        let container = try await Self.makeReadyToSendContainer()
        container.session.userFlags = .fixture(tipPresets: [
            UserFlags.TipPresets(currency: .usd, minimum: 1, low: 5, medium: 10, high: 20),
        ])
        let mock = MockSession()
        mock.resolveContactHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }
        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            target: .contact(Self.makeContact()),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
        viewModel.enteredAmount = "0\(AmountValidator.localizedDecimalSeparator)50"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .success)
        #expect(mock.sendCalls.count == 1)
    }

    // MARK: - Tip floor

    // The fee a recipient sets buys the *conversation*, so it applies to exactly
    // one payment: the tip that opens the DM. Past that the tip card falls back
    // to the regional minimum and the in-chat send carries no floor at all.

    private static let presets = UserFlags.TipPresets(currency: .usd, minimum: 1, low: 5, medium: 10, high: 20)

    /// Funded container with the regional presets seeded, so every floor test
    /// starts with a system minimum for the recipient's fee to override.
    static func makeFloorContainer() async throws -> SessionContainer {
        let container = try await makeReadyToSendContainer()
        container.session.userFlags = .fixture(tipPresets: [presets])
        return container
    }

    /// Writes an existing tip DM into the feed the way a cold start does — the
    /// controller's store is private, so it goes through the cache it hydrates from.
    static func seedTipDM(in container: SessionContainer, with recipientID: UserID) async throws {
        try container.database.upsertConversation(
            Conversation(
                id: .tipDm(between: container.session.userID, and: recipientID),
                members: [
                    ConversationMember(userID: container.session.userID, displayName: "Me"),
                    ConversationMember(userID: recipientID, displayName: "Fred"),
                ],
                lastMessage: nil,
                lastActivity: .now,
                type: .tipDm
            )
        )
        await container.conversationController.hydrateFromDatabase()
    }

    /// A tip recipient's cached profile, carrying the fee they charge to be
    /// written to (none by default).
    static func makeRecipientProfile(fee: FiatAmount? = nil) -> Profile {
        Profile(
            displayName: "Fred",
            phone: Phone?.none,
            email: nil,
            minDmChatInitFee: fee
        )
    }

    static func makeTipViewModel(
        container: SessionContainer,
        recipientID: UserID,
        origin: TipOrigin,
        mock: MockSession = MockSession()
    ) -> SendAmountViewModel {
        SendAmountViewModel(
            sessionContainer: container,
            target: .tip(TipRecipient(userID: recipientID, displayName: "Fred", origin: origin)),
            mint: .usdf,
            sender: mock,
            resolver: mock
        )
    }

    @Test("The tip that opens a DM from chat has to clear the recipient's own fee")
    func tipFloor_chatOpeningDM_isRecipientFee() async throws {
        let container = try await Self.makeFloorContainer()
        let recipientID = UUID()
        container.session.cacheUserProfile(
            Self.makeRecipientProfile(fee: .usd(5)),
            for: recipientID
        )

        let viewModel = Self.makeTipViewModel(container: container, recipientID: recipientID, origin: .chat)

        #expect(viewModel.opensTipDM)
        #expect(viewModel.tipFloor(in: .usd) == .recipientFee(.usd(5)))
        #expect(viewModel.tipMinimum == .usd(5))
    }

    @Test("A recipient who charges nothing still carries the regional minimum")
    func tipFloor_chatOpeningDM_noFee_isPreset() async throws {
        let container = try await Self.makeFloorContainer()
        let recipientID = UUID()
        container.session.cacheUserProfile(
            Self.makeRecipientProfile(),
            for: recipientID
        )

        let viewModel = Self.makeTipViewModel(container: container, recipientID: recipientID, origin: .chat)

        #expect(viewModel.opensTipDM)
        #expect(viewModel.tipFloor(in: .usd) == .preset(Self.presets))
    }

    @Test("Once the DM exists, an in-chat send carries no floor at all")
    func tipFloor_chatExistingDM_hasNoFloor() async throws {
        let container = try await Self.makeFloorContainer()
        let recipientID = UUID()
        try await Self.seedTipDM(in: container, with: recipientID)
        container.session.cacheUserProfile(
            Self.makeRecipientProfile(fee: .usd(5)),
            for: recipientID
        )

        let mock = MockSession()
        mock.resolveUserIDHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }
        let viewModel = Self.makeTipViewModel(
            container: container,
            recipientID: recipientID,
            origin: .chat,
            mock: mock
        )
        viewModel.enteredAmount = "0\(AmountValidator.localizedDecimalSeparator)50"

        #expect(!viewModel.opensTipDM)
        #expect(viewModel.tipFloor(in: .usd) == nil)
        #expect(viewModel.tipMinimum == nil)

        // The fee bought the conversation; a later tip in the same thread is a
        // plain send, so 50c goes through under both the $5 fee and the $1 preset.
        let outcome = await viewModel.sendAction()
        #expect(outcome == .success)
        #expect(mock.sendCalls.count == 1)
    }

    @Test("Once the DM exists, the tip card falls back to the regional minimum")
    func tipFloor_tipcardExistingDM_isSystemMinimum() async throws {
        let container = try await Self.makeFloorContainer()
        let recipientID = UUID()
        try await Self.seedTipDM(in: container, with: recipientID)
        container.session.cacheUserProfile(
            Self.makeRecipientProfile(fee: .usd(5)),
            for: recipientID
        )

        let viewModel = Self.makeTipViewModel(container: container, recipientID: recipientID, origin: .tipcard)

        #expect(!viewModel.opensTipDM)
        #expect(viewModel.tipFloor(in: .usd) == .preset(Self.presets))
    }

    @Test("A tip card tip that opens the DM is blocked below the recipient's fee")
    func tipFloor_tipcardOpeningDM_blocksBelowFee() async throws {
        let container = try await Self.makeFloorContainer()
        let recipientID = UUID()
        container.session.cacheUserProfile(
            Self.makeRecipientProfile(fee: .usd(5)),
            for: recipientID
        )

        let mock = MockSession()
        mock.resolveUserIDHandler = { _ in Self.recipient }
        mock.sendHandler = { _, _, _ in }
        let viewModel = Self.makeTipViewModel(
            container: container,
            recipientID: recipientID,
            origin: .tipcard,
            mock: mock
        )
        // Over the $1 regional minimum, under the $5 the recipient charges.
        viewModel.enteredAmount = "2"

        let outcome = await viewModel.sendAction()

        #expect(outcome == .failed)
        #expect(mock.sendCalls.isEmpty)
        #expect(container.session.dialogItem?.title == "$5.00 Minimum Tip")
    }

    @Test("A contact send has no tip floor and never says Swipe to Tip")
    func tipFloor_contactTarget_isNil() async throws {
        let container = try await Self.makeFloorContainer()

        let viewModel = SendAmountViewModel(
            sessionContainer: container,
            target: .contact(Self.makeContact()),
            mint: .usdf
        )

        #expect(!viewModel.opensTipDM)
        #expect(viewModel.tipFloor(in: .usd) == nil)
    }
}
