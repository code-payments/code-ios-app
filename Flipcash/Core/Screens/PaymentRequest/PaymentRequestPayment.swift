//
//  PaymentRequestPayment.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Pays the viewer's share of one payment request to its creator.
///
/// The share is paid under the intent ID the server issued for it, so a retry, a second tap or a
/// second device can land only once. That ID is held in memory for this payment only and never
/// logged: anyone holding it before the share is paid can use it up.
@MainActor
@Observable
final class PaymentRequestPayment {

    enum Outcome: Equatable {
        case success
        case failed
    }

    /// What ``prepare()`` found.
    enum Preparation: Equatable {
        /// The share is payable; show the swipe sheet.
        case ready
        /// The viewer has no unpaid share any more; the screen already shows the fetched request.
        case nothingToPay
        /// The request stopped accepting payments; "Request Closed" was shown.
        case closed
        case failed
    }

    let requestID: PaymentRequestID

    private(set) var selectedBalance: ExchangedBalance?

    @ObservationIgnored private let requests: PaymentRequests
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let payer: any RequestedPaying
    @ObservationIgnored private let resolver: any RecipientResolving
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var intentID: Data?
    /// Set after a payment whose outcome isn't known, so the next try refetches first.
    @ObservationIgnored private var needsRefetch = false

    init(
        requestID: PaymentRequestID,
        sessionContainer: SessionContainer,
        payer: (any RequestedPaying)? = nil,
        resolver: (any RecipientResolving)? = nil,
        clock: @escaping () -> Date = Date.init
    ) {
        let session = sessionContainer.session
        self.requestID = requestID
        self.requests = sessionContainer.paymentRequests
        self.session = session
        self.ratesController = sessionContainer.ratesController
        self.payer = payer ?? session
        self.resolver = resolver ?? session
        self.clock = clock
        self.selectedBalance = sessionContainer.ratesController.resolveInitialBalance(mint: nil, session: session)
    }

    var request: GroupPaymentRequest? {
        requests.request(requestID)
    }

    /// The viewer's unpaid share, nil once paid.
    var share: GroupPaymentRequest.Share? {
        guard let own = request?.share(for: session.userID), !own.isPaid else { return nil }
        return own
    }

    func selectCurrencyAction(exchangedBalance: ExchangedBalance) {
        selectedBalance = exchangedBalance
    }

    /// Refetches the request right before the swipe sheet shows, taking the intent ID from it.
    func prepare() async -> Preparation {
        do {
            intentID = try await requests.refresh(requestID)
        } catch {
            showSendError()
            return .failed
        }
        needsRefetch = false
        if !isOpen {
            intentID = nil
            showRequestClosed()
            return .closed
        }
        return intentID != nil && share != nil ? .ready : .nothingToPay
    }

    /// Pays exactly the share: its amount in the request's currency, priced into the picked token.
    func submit() async -> Outcome {
        if needsRefetch {
            switch await prepare() {
            case .ready: break
            case .nothingToPay, .closed, .failed: return .failed
            }
        }
        guard let request, let share, let creator = request.creator,
              let intentID, let intentKey = try? PublicKey(intentID),
              let chatID = request.chatID,
              let currency = request.split.flatMap({ try? CurrencyCode(currencyCode: $0.currency) }),
              let value = Decimal(string: "\(share.nativeAmount)") else {
            showSendError()
            return .failed
        }

        guard let selectedBalance else {
            ErrorReporting.captureError(
                GroupSendViewModel.Error.noSpendableBalance,
                reason: "No spendable balance at request payment",
                metadata: ["conversationID": chatID.description]
            )
            showSendError()
            return .failed
        }

        let mint = selectedBalance.stored.mint
        guard let pin = await ratesController.currentPinnedState(for: currency, mint: mint),
              let amount = session.price(FiatAmount(value: value, currency: currency), mint: mint, at: pin) else {
            ErrorReporting.captureError(
                RatesController.Error.exchangeRateUnavailable,
                reason: "No fresh rate at request payment",
                metadata: ["mint": mint.base58]
            )
            session.dialogItem = .error(
                title: "Rate Unavailable",
                subtitle: "Couldn't get a fresh rate. Please try again."
            )
            return .failed
        }

        switch session.hasSufficientFunds(for: amount) {
        case .insufficient(let shortfall):
            if let shortfall {
                session.dialogItem = .error(
                    title: "You're \(shortfall.nativeAmount.formatted()) Short",
                    subtitle: "Add more cash, or try again with a lower amount"
                )
            } else {
                session.dialogItem = .error(
                    title: "You Need More Cash",
                    subtitle: "Please add more cash, or try again with a lower amount"
                )
            }
            return .failed
        case .sufficient:
            break
        }

        let sendLimit = session.sendLimitFor(currency: amount.nativeAmount.currency) ?? .zero
        guard amount.nativeAmount.value <= sendLimit.nextTransaction.value else {
            session.dialogItem = .error(
                title: "Transaction Limit Reached",
                subtitle: "Flipcash is designed for small, every day transactions. Send limits reset daily"
            )
            return .failed
        }

        let creatorOwner: PublicKey
        do {
            creatorOwner = try await resolver.resolveUserID(creator)
        } catch {
            showSendError()
            return .failed
        }

        do {
            try await payer.payRequestShare(
                amount: amount,
                verifiedState: pin,
                to: creatorOwner,
                chatID: chatID,
                paymentRequestID: requestID,
                intentID: intentKey
            )
            self.intentID = nil
            Analytics.transfer(event: .sentCash, exchangedFiat: amount, grabTime: nil, successful: true, error: nil)
            try? await requests.refresh(requestID)
            return .success
        } catch {
            Analytics.transfer(event: .sentCash, exchangedFiat: amount, grabTime: nil, successful: false, error: error)
            needsRefetch = true
            guard !(error is CancellationError) else { return .failed }
            // A refusal because the request ended reads as "Request Closed", not a send failure.
            try? await requests.refresh(requestID)
            if isOpen {
                showSendError()
            } else {
                self.intentID = nil
                showRequestClosed()
            }
            return .failed
        }
    }

    private var isOpen: Bool {
        guard let request else { return false }
        switch request.effectiveStatus(at: clock()) {
        case .open:                                    return true
        case .completed, .closed, .expired, .unknown:  return false
        }
    }

    private func showRequestClosed() {
        session.dialogItem = .error(
            title: "Request Closed",
            subtitle: "This request is no longer accepting payments."
        )
    }

    private func showSendError() {
        session.dialogItem = .error(
            title: "Couldn't Send",
            subtitle: "We couldn't complete the transfer. Please try again."
        )
    }
}
