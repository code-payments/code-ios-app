//
//  SendBackController.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// What Send Back needs from the session, behind a protocol so the controller is testable.
@MainActor
protocol SendBackServicing: AnyObject {
    /// `GetCashMessageReturnStatus` for `messageID` in `conversationID`, as the viewer.
    func cashMessageReturnStatus(conversationID: ConversationID, messageID: MessageID) async throws -> CashReturnStatus
    /// `original` re-priced in its own currency and mint at today's rate, with the proof it was
    /// priced at; nil when no fresh rate is available.
    func priceReturn(of original: ExchangedFiat) async -> (amount: ExchangedFiat, pin: VerifiedState)?
    /// The quarks of `mint` the viewer holds; nil when no balance of `mint` is loaded.
    func heldQuarks(of mint: PublicKey) -> UInt64?
    /// The shortfall to show in the insufficient-balance modal, when the session can name it.
    func hasSufficientFunds(for amount: ExchangedFiat) -> Session.SufficientFundsResult
    /// The token's name and icon from its mint metadata; nil when the metadata can't be loaded.
    func tokenLabel(for mint: PublicKey) async -> (name: String, iconURL: URL?)?
    /// The owner account of `userID`, where the return is paid.
    func resolveUserID(_ userID: UserID) async throws -> PublicKey
    func returnPayment(amount: ExchangedFiat, verifiedState: VerifiedState, to senderOwner: PublicKey, chatID: ConversationID, messageID: MessageID, intentID: PublicKey) async throws
}

/// What Send Back reports to analytics. Never carries the intent, chat or message id.
@MainActor
protocol SendBackAnalytics: AnyObject {
    /// `Send Back: Tapped`, after the balance check and before the sheet or modal.
    func tapped(hasBalance: Bool)
    /// `Sent Cash` with the `Send Back` context, once per swipe.
    func sent(_ outcome: SendBackOutcome, amount: ExchangedFiat)
}

/// How a swiped return ended, as `Sent Cash` reports it.
enum SendBackOutcome {
    case success
    /// The server says the payment was already sent back, by an earlier tap or another device.
    case alreadyReturned
    case failed(Error)
}

/// What Send Back shows that is not a transcript row, so tests can observe it.
@MainActor
protocol SendBackPresenting: AnyObject {
    /// The existing insufficient-balance modal: "You're $X Short" when the shortfall is known, else
    /// "You Need More Cash". Its Add More Cash opens deposit for `mint`.
    func showInsufficientBalance(shortfall: ExchangedFiat?, mint: PublicKey)
    /// "Couldn't Send Back" / "Something went wrong. Please try again."
    func showSendBackError()
    /// No fresh rate to price the return; the app's standard "Rate Unavailable".
    func showRateUnavailable()
}

/// The offer the confirm sheet shows and the swipe returns.
struct SendBackOffer: Identifiable, Equatable {
    let conversationID: ConversationID
    let messageID: MessageID
    /// The original sender, who is paid the return.
    let senderID: UserID
    /// The original's total, in its currency and mint.
    let original: ExchangedFiat
    /// The DM peer's display name, as the chat title shows it.
    let recipientName: String
    var token: String
    var iconURL: URL?

    var id: MessageID { messageID }
}

/// Send Back for one DM open: the one status check per offered message, the row state, the
/// confirm-sheet gates, and the submit. The intent id lives here, in memory, for this open only.
@MainActor
@Observable
final class SendBackController {

    /// Each offered message's state this open, keyed by message id. Read by the coordinator inside
    /// its observation scope, so a change re-maps the row.
    private(set) var states: [MessageID: SendBackRow.Local] = [:]

    /// The server's intent id per message. Never logged, persisted, reported, or put in analytics.
    @ObservationIgnored private var intentIDs: [MessageID: PublicKey] = [:]
    @ObservationIgnored private var asked: Set<MessageID> = []

    @ObservationIgnored let conversationID: ConversationID
    @ObservationIgnored private let services: any SendBackServicing
    @ObservationIgnored private let analytics: any SendBackAnalytics
    @ObservationIgnored private let presenter: any SendBackPresenting

    /// The submit of the last swipe, kept so a test can wait for it.
    @ObservationIgnored private(set) var submitTask: Task<Void, Never>?
    /// The last status check started, kept so a test can wait for it.
    @ObservationIgnored private(set) var statusTask: Task<Void, Never>?

    init(conversationID: ConversationID, services: any SendBackServicing, analytics: any SendBackAnalytics, presenter: any SendBackPresenting) {
        self.conversationID = conversationID
        self.services = services
        self.analytics = analytics
        self.presenter = presenter
    }

    func local(for messageID: MessageID) -> SendBackRow.Local {
        states[messageID] ?? .unknown
    }

    // MARK: - Status -

    /// Asks the server about `messageID` once this open. A failed check leaves the row hidden and
    /// is not retried until the DM opens again; no error is shown.
    func checkStatusIfNeeded(_ messageID: MessageID) {
        guard asked.insert(messageID).inserted else { return }
        statusTask = Task { await self.fetchStatus(messageID, updatingRow: true) }
    }

    /// The status, or nil when the call failed. With `updatingRow`, an answer moves a row that is
    /// not mid-submit.
    @discardableResult
    private func fetchStatus(_ messageID: MessageID, updatingRow: Bool) async -> CashReturnStatus.State? {
        let status: CashReturnStatus
        do {
            status = try await services.cashMessageReturnStatus(conversationID: conversationID, messageID: messageID)
        } catch {
            return nil
        }
        switch status.state {
        case .available:
            if let data = status.paymentIntentID, let key = try? PublicKey(data) {
                intentIDs[messageID] = key
            }
            if updatingRow, local(for: messageID) == .unknown {
                states[messageID] = .available
            }
        case .returned:
            intentIDs[messageID] = nil
            if updatingRow { states[messageID] = .sentBack }
        case .unknown:
            break
        }
        return status.state
    }

    // MARK: - Tap -

    /// The tap on Send Back. Returns the offer to confirm, or nil when the balance is short (the
    /// modal is up instead) or the return could not be priced.
    func tap(_ offer: SendBackOffer) async -> SendBackOffer? {
        // One tap at a time: a double tap would report Send Back: Tapped twice and open the sheet twice.
        guard !tapInFlight, local(for: offer.messageID) == .available else { return nil }
        tapInFlight = true
        defer { tapInFlight = false }
        guard let priced = await services.priceReturn(of: offer.original) else {
            presenter.showRateUnavailable()
            return nil
        }
        // A tap whose balance can't be determined reaches neither the sheet nor the modal, so the
        // funnel doesn't count it.
        guard let hasBalance = checkBalance(priced.amount) else {
            presenter.showRateUnavailable()
            return nil
        }
        analytics.tapped(hasBalance: hasBalance)
        guard hasBalance else { return nil }
        var confirmed = offer
        if let token = await services.tokenLabel(for: offer.original.mint) {
            confirmed.token = token.name
            confirmed.iconURL = token.iconURL
        }
        return confirmed
    }

    private var tapInFlight = false

    // MARK: - Swipe -

    enum ConfirmOutcome: Equatable {
        /// The return is submitting; the row shows Sending.
        case submitted
        /// Not submitted: the balance fell short (the modal is up) or no rate. The row stays Available.
        case blocked
    }

    /// The swipe. Checks the balance again, since it can change while the sheet is open, then
    /// starts the submit. The sheet dismisses either way.
    func confirm(_ offer: SendBackOffer) async -> ConfirmOutcome {
        guard local(for: offer.messageID) == .available else { return .blocked }
        guard let priced = await services.priceReturn(of: offer.original) else {
            presenter.showRateUnavailable()
            return .blocked
        }
        switch checkBalance(priced.amount) {
        case true?: break
        case false?: return .blocked
        case nil:
            presenter.showRateUnavailable()
            return .blocked
        }
        states[offer.messageID] = .sending
        submitTask = Task { await self.submit(offer, amount: priced.amount, pin: priced.pin) }
        return .submitted
    }

    /// Whether the held quarks cover `amount`'s quarks; when they don't, shows the
    /// insufficient-balance modal. Nil, with nothing shown, when no balance of the mint is loaded.
    ///
    /// Strict on purpose: the return pays exactly `amount`. `Session.hasSufficientFunds` forgives a
    /// shortfall under half a denomination because its callers send its `amountToSend` instead;
    /// this one can't, so a balance a fraction of a cent short would fail on chain.
    private func checkBalance(_ amount: ExchangedFiat) -> Bool? {
        guard let held = services.heldQuarks(of: amount.mint) else { return nil }
        let needed = amount.onChainAmount.quarks
        if needed > 0, held >= needed {
            return true
        }
        var shortfall: ExchangedFiat?
        if case .insufficient(let known) = services.hasSufficientFunds(for: amount) {
            shortfall = known
        }
        presenter.showInsufficientBalance(shortfall: shortfall, mint: amount.mint)
        return false
    }

    private func submit(_ offer: SendBackOffer, amount: ExchangedFiat, pin: VerifiedState) async {
        let messageID = offer.messageID

        // 1. The intent id from this open's check, else ask now.
        if intentIDs[messageID] == nil {
            switch await fetchStatus(messageID, updatingRow: false) {
            case .returned:
                states[messageID] = .sentBack
                analytics.sent(.alreadyReturned, amount: amount)
                return
            default:
                break
            }
        }
        guard let intentID = intentIDs[messageID] else {
            fail(messageID, amount: amount, error: SendBackError.intentUnavailable)
            return
        }

        // 2. Pay the original sender's owner under the server's intent id.
        do {
            let owner = try await services.resolveUserID(offer.senderID)
            try await services.returnPayment(
                amount: amount,
                verifiedState: pin,
                to: owner,
                chatID: offer.conversationID,
                messageID: messageID,
                intentID: intentID
            )
        } catch {
            // 4. A failure that the server already counts as returned is a success to the viewer.
            if await fetchStatus(messageID, updatingRow: false) == .returned {
                states[messageID] = .sentBack
                analytics.sent(.alreadyReturned, amount: amount)
            } else {
                fail(messageID, amount: amount, error: error)
            }
            return
        }

        // 3. The return message arrives through the stream; the row moves now.
        intentIDs[messageID] = nil
        states[messageID] = .sentBack
        analytics.sent(.success, amount: amount)
    }

    private func fail(_ messageID: MessageID, amount: ExchangedFiat, error: Error) {
        states[messageID] = .available
        analytics.sent(.failed(error), amount: amount)
        presenter.showSendBackError()
    }
}

enum SendBackError: Error {
    /// The status check gave no intent id to submit the return under.
    case intentUnavailable
}
