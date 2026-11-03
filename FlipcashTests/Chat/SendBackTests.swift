//
//  SendBackTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

// MARK: - Fixtures -

private let me = UserID()
private let alex = UserID()
private let chat = ConversationID.test(7)

private let five = ExchangedFiat(
    onChainAmount: TokenAmount(quarks: 5_000_000, mint: .usdf),
    nativeAmount: FiatAmount(value: 5, currency: .usd),
    currencyRate: Rate(fx: 1, currency: .usd)
)

private func cash(
    _ id: UInt64,
    from sender: UserID,
    to receiver: UserID?,
    _ cashReturn: CashReturn? = nil
) -> ConversationMessage {
    ConversationMessage(
        id: MessageID(value: id),
        senderID: sender,
        content: .cash(five),
        cashReceiverID: receiver,
        cashReturn: cashReturn,
        date: Date(timeIntervalSince1970: TimeInterval(id)),
        unreadSeq: id
    )
}

private let offer = CashReturn(hasOffer: true, returnOf: nil)
private func returning(_ id: UInt64) -> CashReturn {
    CashReturn(hasOffer: false, returnOf: .init(messageID: MessageID(value: id)))
}

// MARK: - Row -

@Suite("Send Back row")
struct SendBackRowTests {

    private func row(_ message: ConversationMessage, in window: [ConversationMessage]? = nil, viewer: UserID = me, local: SendBackRow.Local = .unknown) -> ChatCashContent.SendBack? {
        SendBackRow.resolve(message, selfUserID: viewer, returnedIDs: SendBackRow.returnedIDs(in: window ?? [message]), local: local)
    }

    private func needsStatus(_ message: ConversationMessage, in window: [ConversationMessage]? = nil, viewer: UserID = me) -> Bool {
        SendBackRow.needsStatus(message, selfUserID: viewer, returnedIDs: SendBackRow.returnedIDs(in: window ?? [message]))
    }

    @Test("1: an offer to the viewer whose status is AVAILABLE shows Send Back")
    func receiver_available() {
        let original = cash(1, from: alex, to: me, offer)
        #expect(needsStatus(original))
        #expect(row(original, local: .available) == .available)
    }

    @Test("2: the sender of an offer sees no row and asks nothing")
    func sender_noRow() {
        let original = cash(1, from: me, to: alex, offer)
        #expect(!needsStatus(original))
        #expect(row(original, local: .available) == nil)
    }

    @Test("3: a cash message with no offer shows no row and asks nothing")
    func noOffer() {
        let plain = cash(1, from: alex, to: me)
        #expect(!needsStatus(plain))
        #expect(row(plain, local: .available) == nil)
    }

    @Test("4: a later message returning the offer shows Sent Back and skips the status check")
    func receiver_returnedInTranscript() {
        let original = cash(1, from: alex, to: me, offer)
        let window = [original, cash(2, from: me, to: alex, returning(1))]
        #expect(!needsStatus(original, in: window))
        #expect(row(original, in: window) == .sentBack)
    }

    @Test("5: status RETURNED shows Sent Back")
    func receiver_statusReturned() {
        #expect(row(cash(1, from: alex, to: me, offer), local: .sentBack) == .sentBack)
    }

    @Test("6: the original sender sees Sent Back on their bubble once a later message returns it")
    func sender_returnedInTranscript() {
        let original = cash(1, from: me, to: alex, offer)
        let window = [original, cash(2, from: alex, to: me, returning(1))]
        #expect(!needsStatus(original, in: window))
        #expect(row(original, in: window) == .sentBack)
    }

    @Test("While the status is unknown the row stays hidden; Sending shows the spinner state")
    func receiver_unknownAndSending() {
        let original = cash(1, from: alex, to: me, offer)
        #expect(row(original, local: .unknown) == nil)
        #expect(row(original, local: .sending) == .sending)
    }

    @Test("A return message that also carries an offer follows the offered-bubble rules")
    func returnWithOffer() {
        let both = cash(3, from: alex, to: me, CashReturn(hasOffer: true, returnOf: .init(messageID: MessageID(value: 1))))
        #expect(needsStatus(both))
        #expect(row(both, local: .available) == .available)
    }
}

// MARK: - Return captions -

@Suite("Send Back return captions")
struct SendBackCaptionTests {

    private func lines(_ message: ConversationMessage) -> ChatCashContent.Lines? {
        ChatItem.from([message], selfUserID: me, counterpartName: "Alex Morgan").compactMap {
            if case .message(let m) = $0, case .cash(let cash) = m.content { cash.lines } else { nil }
        }.first
    }

    @Test("8: the sender of a return reads 'You sent back' / 'to <Name>'")
    func returnSender() {
        let line = lines(cash(2, from: me, to: alex, returning(1)))
        #expect(line?.caption == "You sent back")
        #expect(line?.counterpart == "to Alex Morgan")
    }

    @Test("9: the receiver of a return reads '<Name> sent back' / 'to you'")
    func returnReceiver() {
        let line = lines(cash(2, from: alex, to: me, returning(1)))
        #expect(line?.caption == "Alex Morgan sent back")
        #expect(line?.counterpart == "to you")
    }

    @Test("A return draws no Send Back row of its own")
    func returnHasNoRow() {
        let message = cash(2, from: alex, to: me, returning(1))
        #expect(SendBackRow.resolve(message, selfUserID: me, returnedIDs: [], local: .available) == nil)
    }
}

// MARK: - Controller -

@MainActor
private final class FakeServices: SendBackServicing {
    var statuses: [CashReturnStatus.State] = []
    var statusError: Error?
    var statusCalls = 0
    var shortfall: ExchangedFiat?? = nil
    var payError: Error?
    var withholdIntent = false
    var owner = PublicKey.testMint(index: 42)
    struct Payment { let amount: ExchangedFiat; let to: PublicKey; let chatID: ConversationID; let messageID: MessageID; let intentID: PublicKey }
    var payments: [Payment] = []
    static let intent = PublicKey.testMint(index: 99)

    func cashMessageReturnStatus(conversationID: ConversationID, messageID: MessageID) async throws -> CashReturnStatus {
        statusCalls += 1
        if let statusError { throw statusError }
        let state = statuses.isEmpty ? .available : statuses.removeFirst()
        return CashReturnStatus(state: state, paymentIntentID: state == .available && !withholdIntent ? Self.intent.data : nil)
    }

    func priceReturn(of original: ExchangedFiat) async -> (amount: ExchangedFiat, pin: VerifiedState)? {
        (original, .stale(bonded: false))
    }

    func hasSufficientFunds(for amount: ExchangedFiat) -> Session.SufficientFundsResult {
        if let shortfall { return .insufficient(shortfall: shortfall) }
        return .sufficient(amountToSend: amount)
    }

    func resolveUserID(_ userID: UserID) async throws -> PublicKey { owner }

    func returnPayment(amount: ExchangedFiat, verifiedState: VerifiedState, to senderOwner: PublicKey, chatID: ConversationID, messageID: MessageID, intentID: PublicKey) async throws {
        payments.append(.init(amount: amount, to: senderOwner, chatID: chatID, messageID: messageID, intentID: intentID))
        if let payError { throw payError }
    }
}

@MainActor
private final class FakeAnalytics: SendBackAnalytics {
    var taps: [Bool] = []
    var sent: [String] = []
    func tapped(hasBalance: Bool) { taps.append(hasBalance) }
    func sent(_ outcome: SendBackOutcome, amount: ExchangedFiat) {
        switch outcome {
        case .success: sent.append("success")
        case .alreadyReturned: sent.append("alreadyReturned")
        case .failed: sent.append("failed")
        }
    }
}

@MainActor
private final class FakePresenter: SendBackPresenting {
    var shown: [String] = []
    func showInsufficientBalance(shortfall: ExchangedFiat?, mint: PublicKey) { shown.append("insufficient") }
    func showSendBackError() { shown.append("error") }
    func showRateUnavailable() { shown.append("rate") }
}

private struct Boom: Error {}

@MainActor
@Suite("Send Back controller")
struct SendBackControllerTests {

    fileprivate let services = FakeServices()
    fileprivate let analytics = FakeAnalytics()
    fileprivate let presenter = FakePresenter()
    let messageID = MessageID(value: 1)

    private func controller() -> SendBackController {
        SendBackController(conversationID: chat, services: services, analytics: analytics, presenter: presenter)
    }

    private var sendBackOffer: SendBackOffer {
        SendBackOffer(conversationID: chat, messageID: messageID, senderID: alex, original: five, recipientName: "Alex Morgan", token: "USD Coin", iconURL: nil)
    }

    /// Runs the open's status check and returns a controller whose row is `state`.
    private func opened() async -> SendBackController {
        let controller = controller()
        controller.checkStatusIfNeeded(messageID)
        await controller.statusTask?.value
        return controller
    }

    @Test("1: the open's status check asks once and AVAILABLE makes the row available")
    func statusAvailable() async {
        let controller = await opened()
        controller.checkStatusIfNeeded(messageID)
        #expect(services.statusCalls == 1)
        #expect(controller.local(for: messageID) == .available)
    }

    @Test("5: status RETURNED makes the row Sent Back")
    func statusReturned() async {
        services.statuses = [.returned]
        let controller = await opened()
        #expect(controller.local(for: messageID) == .sentBack)
    }

    @Test("7: a failed status check leaves the row hidden and shows nothing")
    func statusFails() async {
        services.statusError = Boom()
        let controller = await opened()
        #expect(controller.local(for: messageID) == .unknown)
        #expect(presenter.shown.isEmpty)
    }

    @Test("10: a tap with enough balance confirms the offer, naming the recipient, and reports Has Balance")
    func tapWithBalance() async {
        let controller = await opened()
        let confirmed = await controller.tap(sendBackOffer)
        #expect(confirmed?.recipientName == "Alex Morgan")
        #expect(analytics.taps == [true])
        #expect(presenter.shown.isEmpty)
    }

    @Test("11: a tap short of balance opens no sheet, shows the insufficient-balance modal, and reports no balance")
    func tapShort() async {
        let controller = await opened()
        services.shortfall = .some(five)
        #expect(await controller.tap(sendBackOffer) == nil)
        #expect(presenter.shown == ["insufficient"])
        #expect(analytics.taps == [false])
    }

    @Test("12: the return pays the original's amount to the sender's owner, in the DM, under the server's intent id")
    func returnIntent() async throws {
        let controller = await opened()
        #expect(await controller.confirm(sendBackOffer) == .submitted)
        await controller.submitTask?.value
        let payment = try #require(services.payments.first)
        #expect(payment.messageID == messageID)
        #expect(payment.chatID == chat)
        #expect(payment.to == services.owner)
        #expect(payment.amount.mint == five.mint)
        #expect(payment.amount.nativeAmount == five.nativeAmount)
        #expect(payment.intentID == FakeServices.intent)
    }

    @Test("13: a swipe shows Sending, then Sent Back on success, and reports Success")
    func submitSucceeds() async {
        let controller = await opened()
        _ = await controller.confirm(sendBackOffer)
        #expect(controller.local(for: messageID) == .sending)
        await controller.submitTask?.value
        #expect(controller.local(for: messageID) == .sentBack)
        #expect(analytics.sent == ["success"])
    }

    @Test("14: a failed submit that the re-check finds RETURNED shows Sent Back, no error, Already Returned")
    func submitFailsAlreadyReturned() async {
        let controller = await opened()
        services.payError = Boom()
        services.statuses = [.returned]
        _ = await controller.confirm(sendBackOffer)
        await controller.submitTask?.value
        #expect(controller.local(for: messageID) == .sentBack)
        #expect(presenter.shown.isEmpty)
        #expect(analytics.sent == ["alreadyReturned"])
    }

    @Test("15: a failed submit that the re-check finds AVAILABLE returns the row and shows Couldn't Send Back")
    func submitFailsAvailable() async {
        let controller = await opened()
        services.payError = Boom()
        services.statuses = [.available]
        _ = await controller.confirm(sendBackOffer)
        await controller.submitTask?.value
        #expect(controller.local(for: messageID) == .available)
        #expect(presenter.shown == ["error"])
        #expect(analytics.sent == ["failed"])
        #expect(services.statusCalls == 2)
    }

    @Test("Step 1: with no intent id from the open, the swipe asks; RETURNED is Sent Back, Already Returned, no payment")
    func submitNoIntentReturned() async {
        services.withholdIntent = true
        let controller = await opened()
        services.statuses = [.returned]
        _ = await controller.confirm(sendBackOffer)
        await controller.submitTask?.value
        #expect(controller.local(for: messageID) == .sentBack)
        #expect(services.payments.isEmpty)
        #expect(analytics.sent == ["alreadyReturned"])
        #expect(presenter.shown.isEmpty)
    }

    @Test("19: the balance dropping while the sheet is open blocks the swipe: no submit, row Available, modal")
    func balanceDropsBeforeSwipe() async {
        let controller = await opened()
        #expect(await controller.tap(sendBackOffer) != nil)
        services.shortfall = .some(nil)
        #expect(await controller.confirm(sendBackOffer) == .blocked)
        #expect(controller.local(for: messageID) == .available)
        #expect(presenter.shown == ["insufficient"])
        #expect(services.payments.isEmpty)
        #expect(controller.submitTask == nil)
    }
}

// MARK: - Intent id privacy -

@Suite("Send Back intent id privacy")
struct SendBackPrivacyTests {

    @Test("18: a server-issued intent id never reaches the payment logs, and a failed return reports as Send back")
    func intentNeverLogged() {
        let intent = PublicKey.testMint(index: 99)
        #expect(Session.rendezvousLogValue(intent, serverIssued: true) == "server-issued")
        #expect(!Session.rendezvousLogValue(intent, serverIssued: true).contains(intent.base58))
        #expect(Session.rendezvousLogValue(intent, serverIssued: false) == intent.base58)
        #expect(Session.serverIssuedFailureReason(.returnPayment(chatID: chat, messageID: MessageID(value: 1))) == "Send back failed")
    }
}
