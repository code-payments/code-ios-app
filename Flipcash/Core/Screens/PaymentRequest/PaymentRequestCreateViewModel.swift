//
//  PaymentRequestCreateViewModel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.payment-request-create")

/// A new request in a private group: the per-person amount, its name, who is asked and when it
/// closes, then the create call and the widget that puts it in the chat.
@MainActor
@Observable
final class PaymentRequestCreateViewModel {

    enum Outcome: Equatable {
        case sent
        /// The request exists but its chat message never went out; the deck still shows it.
        case messageFailed
        case failed(DialogCopy)
    }

    /// The title and body of an alert raised by a failed create.
    struct DialogCopy: Equatable {
        let title: String
        let subtitle: String
    }

    var enteredAmount: String = ""
    var title: String
    var deadline: PaymentRequestDeadline = .oneWeek
    private(set) var people: PaymentRequestPeople?
    /// Set when checking a member would make a 101st share, until the sheet is dismissed.
    var isShowingPeopleLimit = false
    private(set) var isSending = false

    let conversationID: ConversationID

    /// One key per confirm: every retry of the same send reuses it, so the server creates one request.
    @ObservationIgnored private var idempotencyKey: Data?
    /// The request a confirm created, kept so a retry only resends the message.
    @ObservationIgnored private var created: GroupPaymentRequest?

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let rosters: GroupRosters
    @ObservationIgnored private let conversationController: ConversationController
    @ObservationIgnored private let requests: PaymentRequests
    @ObservationIgnored private let amountValidator = AmountValidator()

    init(sessionContainer: SessionContainer, conversationID: ConversationID) {
        self.session = sessionContainer.session
        self.ratesController = sessionContainer.ratesController
        self.rosters = sessionContainer.groupRosters
        self.conversationController = sessionContainer.conversationController
        self.requests = sessionContainer.paymentRequests
        self.conversationID = conversationID
        self.title = defaultPaymentRequestTitle()
    }

    /// Clears the draft for a fresh New Request: amount, default title and deadline, everyone selected.
    func startNewRequest() {
        enteredAmount = ""
        title = defaultPaymentRequestTitle()
        deadline = .oneWeek
        people = nil
        idempotencyKey = nil
        created = nil
        seedPeopleIfNeeded()
    }

    // MARK: - Amount -

    /// The per-person amount in the display currency, or nil at zero.
    var amount: FiatAmount? {
        guard let value = amountValidator.validate(enteredAmount), value > 0 else { return nil }
        return FiatAmount(value: value, currency: ratesController.balanceCurrency)
    }

    var canContinue: Bool { amount != nil }

    // MARK: - People -

    /// Every member, "You" included, in roster order with the host first.
    var members: [GroupPortrait] {
        let creator = conversationController.conversation(withID: conversationID)?.creator
        return rosters.members(for: conversationID, creator: creator).compactMap { member in
            guard let portrait = GroupPortrait(member, creator: creator) else { return nil }
            guard portrait.userID == session.userID else { return portrait }
            return GroupPortrait(userID: portrait.userID, name: "You", picture: portrait.picture, isHost: portrait.isHost)
        }
    }

    func refreshMembers() async {
        await rosters.refresh(conversationID)
        seedPeopleIfNeeded()
    }

    /// Starts the selection once the roster is known; a refresh after that leaves the user's picks alone.
    func seedPeopleIfNeeded() {
        guard people == nil, !members.isEmpty else { return }
        people = PaymentRequestPeople(members: members.map(\.userID), creator: session.userID)
    }

    func isSelected(_ userID: UserID) -> Bool {
        people?.selected.contains(userID) ?? false
    }

    func toggle(_ userID: UserID) {
        guard var people else { return }
        if !people.toggle(userID) {
            isShowingPeopleLimit = true
        }
        self.people = people
    }

    var peopleValue: String { people?.summaryValue ?? "Choose People" }
    var peopleSecondLine: String? { people?.summarySecondLine }
    var hasValidPeople: Bool { people?.isValid ?? false }
    var canSend: Bool { amount != nil && hasValidPeople && !isSending }

    var sendButtonTitle: String {
        people?.buttonTitle(amount: amount?.formatted() ?? "") ?? "Request"
    }

    // MARK: - Send -

    /// Called when the confirm sheet opens; the key it makes lives until a send succeeds.
    func prepareConfirm() {
        if idempotencyKey == nil {
            idempotencyKey = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        }
    }

    func send(now: Date = .now) async -> Outcome {
        guard let amount, let people, people.isValid else { return .failed(Self.genericError) }
        prepareConfirm()
        guard let idempotencyKey else { return .failed(Self.genericError) }
        isSending = true
        defer { isSending = false }

        let request: GroupPaymentRequest
        if let created {
            request = created
        } else {
            do {
                request = try await create(amount: amount, people: people, key: idempotencyKey, now: now)
                created = request
            } catch let error as ErrorCreatePaymentRequest {
                return .failed(alert(for: error))
            } catch {
                ErrorReporting.captureError(error, reason: "Failed to create payment request")
                return .failed(Self.genericError)
            }
        }

        do {
            try await conversationController.sendPaymentRequest(request.id, in: conversationID)
        } catch {
            finish()
            return .messageFailed
        }
        finish()
        return .sent
    }

    private func create(amount: FiatAmount, people: PaymentRequestPeople, key: Data, now: Date) async throws -> GroupPaymentRequest {
        guard let seal = try await conversationController.photoSeal(for: conversationID) else {
            throw ErrorCreatePaymentRequest.encryptionRequired
        }
        let title = PaymentRequestTitleValidator().validate(title) ?? defaultPaymentRequestTitle(at: now)
        let split = GroupPaymentRequest.Split(
            text: try seal.sealRequestText(title: title, description: ""),
            currency: amount.currency.rawValue.lowercased(),
            endsAt: deadline.endsAt(sentAt: now),
            shares: people.shares(nativeAmount: NSDecimalNumber(decimal: amount.value).doubleValue)
        )
        return try await requests.create(idempotencyKey: key, in: conversationID, split: split)
    }

    /// A finished confirm: the next one, if the flow is reused, is a new request.
    private func finish() {
        idempotencyKey = nil
        created = nil
    }

    private func alert(for error: ErrorCreatePaymentRequest) -> DialogCopy {
        switch error {
        case .denied:
            return DialogCopy(title: "Can't Send Request", subtitle: "You can't request money in this group.")
        case .invalidEndsAt:
            return DialogCopy(title: "Can't Send Request", subtitle: "Choose a deadline within the next 4 weeks.")
        case .invalidShares:
            Task { await refreshMembers() }
            return DialogCopy(title: "Can't Send Request", subtitle: "Someone you included is no longer in the group. Check who's included and try again.")
        case .invalidCurrency:
            return DialogCopy(title: "Can't Send Request", subtitle: "Requests aren't available in this currency yet.")
        case .chatNotSupported, .encryptionNotAllowed, .encryptionRequired, .textModerated, .unknown, .rejected:
            logger.error("Payment request create was refused", metadata: ["result": "\(error)"])
            ErrorReporting.captureError(error, reason: "Payment request create was refused")
            return Self.genericError
        case .transportFailure, .cancelled:
            return Self.networkError
        }
    }

    static let genericError = DialogCopy(title: "Something Went Wrong", subtitle: "Please try again later")
    static let networkError = DialogCopy(title: "No Connection", subtitle: "Check your connection and try again.")
}
