//
//  SendBackServices.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashUI

/// Send Back's session, rates and payment, as the app wires them.
@MainActor
final class LiveSendBackServices: SendBackServicing {

    private let session: Session
    private let ratesController: RatesController

    init(session: Session, ratesController: RatesController) {
        self.session = session
        self.ratesController = ratesController
    }

    func cashMessageReturnStatus(conversationID: ConversationID, messageID: MessageID) async throws -> CashReturnStatus {
        try await session.cashMessageReturnStatus(conversationID: conversationID, messageID: messageID)
    }

    /// The same fiat amount, currency and mint as `original`, at today's rate.
    func priceReturn(of original: ExchangedFiat) async -> (amount: ExchangedFiat, pin: VerifiedState)? {
        guard let pin = await ratesController.currentPinnedState(for: original.nativeAmount.currency, mint: original.mint),
              let amount = session.price(original.nativeAmount, mint: original.mint, at: pin) else {
            return nil
        }
        return (amount, pin)
    }

    func heldQuarks(of mint: PublicKey) -> UInt64 {
        session.balance(for: mint)?.quarks ?? 0
    }

    func hasSufficientFunds(for amount: ExchangedFiat) -> Session.SufficientFundsResult {
        session.hasSufficientFunds(for: amount)
    }

    func tokenLabel(for mint: PublicKey) async -> (name: String, iconURL: URL?)? {
        guard let metadata = try? await session.fetchMintMetadata(mint: mint) else { return nil }
        return (metadata.name, metadata.imageURL)
    }

    func resolveUserID(_ userID: UserID) async throws -> PublicKey {
        try await session.resolveUserID(userID)
    }

    func returnPayment(amount: ExchangedFiat, verifiedState: VerifiedState, to senderOwner: PublicKey, chatID: ConversationID, messageID: MessageID, intentID: PublicKey) async throws {
        try await session.returnPayment(amount: amount, verifiedState: verifiedState, to: senderOwner, chatID: chatID, messageID: messageID, intentID: intentID)
    }
}

/// Send Back's modals, on the session's dialog window, so they show over a sheet that is closing.
@MainActor
final class LiveSendBackPresenter: SendBackPresenting {

    private let session: Session
    private let ratesController: RatesController
    private let openDeposit: (PublicKey) -> Void

    init(session: Session, ratesController: RatesController, openDeposit: @escaping (PublicKey) -> Void) {
        self.session = session
        self.ratesController = ratesController
        self.openDeposit = openDeposit
    }

    /// The modal `ReactionBoostViewModel` shows, unchanged.
    func showInsufficientBalance(shortfall: ExchangedFiat?, mint: PublicKey) {
        let openDeposit = openDeposit
        if let shortfall {
            session.dialogItem = .error(
                title: "You're \(ratesController.displayCurrency.amount(shortfall).formatted()) Short",
                subtitle: "Add more cash, or try again with a lower amount"
            ) {
                .destructive("Add More Cash") { openDeposit(mint) };
                .dismiss(kind: .subtle)
            }
        } else {
            session.dialogItem = .error(
                title: "You Need More Cash",
                subtitle: "Please add more cash, or try again with a lower amount"
            ) {
                .destructive("Add More Cash") { openDeposit(mint) };
                .dismiss(kind: .subtle)
            }
        }
    }

    func showSendBackError() {
        session.dialogItem = .error(
            title: "Couldn't Send Back",
            subtitle: "Something went wrong. Please try again."
        )
    }

    func showRateUnavailable() {
        session.dialogItem = .error(
            title: "Rate Unavailable",
            subtitle: "Couldn't get a fresh rate. Please try again."
        )
    }
}

/// Send Back's analytics. The `Send Back` context and `Send Back: Tapped` exist only in a
/// shared-core release that carries them, so this sends nothing until that release is pinned.
@MainActor
final class LiveSendBackAnalytics: SendBackAnalytics {
    func tapped(hasBalance: Bool) {}
    func sent(_ outcome: SendBackOutcome, amount: ExchangedFiat) {}
}
