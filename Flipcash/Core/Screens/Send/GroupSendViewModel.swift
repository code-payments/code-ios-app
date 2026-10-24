//
//  GroupSendViewModel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Sends cash into a private group: the sender enters a total, picks up to ten members, and the total
/// is split between them in the order they were picked. One recipient is a single payment; two or more
/// are one multi-recipient intent, every part priced at one verified state.
@Observable
final class GroupSendViewModel {

    /// Result of a send attempt. `.success` dismisses the sheet; `.failed` keeps it open. Error copy is
    /// surfaced through `session.dialogItem`.
    enum Outcome: Equatable {
        case success
        case failed
    }

    enum Error: Swift.Error {
        case noSpendableBalance
    }

    var enteredAmount: String = ""

    var depositMint: PublicKey?

    private(set) var selectedBalance: ExchangedBalance?

    /// The members picked, in the order they were picked; that order decides who gets a leftover unit.
    private(set) var selection: [UserID] = []

    let conversationID: ConversationID

    @ObservationIgnored let session: Session
    @ObservationIgnored let ratesController: RatesController
    @ObservationIgnored let rosters: GroupRosters
    @ObservationIgnored let conversationController: ConversationController
    @ObservationIgnored let sender: any DirectSending
    @ObservationIgnored let multiSender: any MultiSending
    @ObservationIgnored let resolver: any RecipientResolving
    @ObservationIgnored private let amountValidator = AmountValidator()

    init(
        sessionContainer: SessionContainer,
        conversationID: ConversationID,
        sender: (any DirectSending)? = nil,
        multiSender: (any MultiSending)? = nil,
        resolver: (any RecipientResolving)? = nil
    ) {
        let session = sessionContainer.session
        let ratesController = sessionContainer.ratesController
        self.session = session
        self.ratesController = ratesController
        self.rosters = sessionContainer.groupRosters
        self.conversationController = sessionContainer.conversationController
        self.conversationID = conversationID
        self.sender = sender ?? session
        self.multiSender = multiSender ?? session
        self.resolver = resolver ?? session
        self.selectedBalance = ratesController.resolveInitialBalance(mint: nil, session: session)
    }

    // MARK: - Amount -

    /// The keypad buffer parsed to a positive amount, or nil.
    private var validatedEntered: Decimal? {
        guard let amount = amountValidator.validate(enteredAmount), amount > 0 else { return nil }
        return amount
    }

    /// The entered total, in the currency it was typed in.
    var enteredTotal: FiatAmount? {
        validatedEntered.map { FiatAmount(value: $0, currency: ratesController.balanceCurrency) }
    }

    /// Whether the amount screen can move on to picking people.
    var canContinue: Bool {
        guard let validatedEntered, let selectedBalance else { return false }
        let fiat = selectedBalance.enteredFiat(for: validatedEntered, rate: ratesController.rateForBalanceCurrency())
        return (fiat?.onChainAmount.quarks ?? 0) > 0
    }

    /// What's left to spend in the selected currency.
    var available: ExchangedFiat {
        let rate = ratesController.rateForBalanceCurrency()
        guard let mint = selectedBalance?.stored.mint, let balance = session.balance(for: mint) else {
            return ExchangedFiat.compute(onChainAmount: .zero(mint: .usdf), rate: rate, supplyQuarks: nil)
        }
        return balance.computeExchangedValue(with: rate)
    }

    /// The balances the currency picker offers.
    func selectCurrencyAction(exchangedBalance: ExchangedBalance) {
        selectedBalance = exchangedBalance
        ratesController.selectToken(exchangedBalance.stored.mint)
    }

    // MARK: - People -

    /// The group's members the sender can pay, the sender left out, host first.
    var members: [GroupPortrait] {
        let creator = conversationController.conversation(withID: conversationID)?.creator
        return rosters.members(for: conversationID, creator: creator).compactMap { member in
            guard member.userID != session.userID else { return nil }
            return GroupPortrait(member, creator: creator)
        }
    }

    /// The picked members in selection order, as far as the roster names them.
    var selectedMembers: [GroupPortrait] {
        let byID = Dictionary(members.map { ($0.userID, $0) }, uniquingKeysWith: { first, _ in first })
        return selection.compactMap { byID[$0] }
    }

    func refreshMembers() async {
        await rosters.refresh(conversationID)
    }

    func isSelected(_ userID: UserID) -> Bool {
        selection.contains(userID)
    }

    /// Checks or unchecks a member. An eleventh check is refused with the "10 People Max" notice.
    func toggle(_ userID: UserID) {
        if let index = selection.firstIndex(of: userID) {
            selection.remove(at: index)
            return
        }
        guard selection.count < GroupSendSplit.maxRecipients else {
            session.dialogItem = .info(
                title: "10 People Max",
                subtitle: "The maximum number of people you can send to at once is 10 people"
            )
            return
        }
        selection.append(userID)
    }

    /// "Send to N People", worded for one.
    var sendButtonTitle: String {
        selection.count == 1 ? "Send to 1 Person" : "Send to \(selection.count) People"
    }

    /// The entered total split between the current selection, or nil when it can't be.
    var split: GroupSendSplit? {
        guard let enteredTotal else { return nil }
        return try? GroupSendSplit.split(total: enteredTotal, recipients: selection.count)
    }

    /// The per-person line for the confirm sheet: "$1.00 Each", or "~$0.33 Each" when uneven.
    var eachLabel: String? {
        guard let split, let enteredTotal else { return nil }
        return split.eachLabel(in: enteredTotal.currency)
    }

    /// Whether the selection can go on to confirm; a total too small to split shows the alert instead.
    func confirmSelection() -> Bool {
        guard let enteredTotal else { return false }
        do {
            _ = try GroupSendSplit.split(total: enteredTotal, recipients: selection.count)
            return true
        } catch {
            switch error {
            case .noRecipients, .tooManyRecipients:
                return false
            case .partBelowMinimum:
                showTooSmallToSplitError(total: enteredTotal)
                return false
            }
        }
    }

    // MARK: - Submit -

    /// Splits the total, prices every part at one verified state, and pays the selection.
    func submit() async -> Outcome {
        guard let enteredTotal, let split else { return .failed }

        guard let selectedBalance else {
            ErrorReporting.captureError(
                Error.noSpendableBalance,
                reason: "No spendable balance at group send submission",
                metadata: ["conversationID": conversationID.description]
            )
            session.dialogItem = .error(
                title: "Balance Unavailable",
                subtitle: "We couldn't load your balance. Please try again."
            )
            return .failed
        }

        let mint = selectedBalance.stored.mint
        guard let pin = await ratesController.currentPinnedState(for: enteredTotal.currency, mint: mint),
              let total = session.price(FiatAmount(value: enteredTotal.value, currency: pin.rate.currency), mint: mint, at: pin) else {
            ErrorReporting.captureError(
                RatesController.Error.exchangeRateUnavailable,
                reason: "No fresh rate at group send submission",
                metadata: ["mint": mint.base58]
            )
            session.dialogItem = .error(
                title: "Rate Unavailable",
                subtitle: "Couldn't get a fresh rate. Please try again."
            )
            return .failed
        }

        let parts = split.amounts(in: pin.rate.currency).map { session.price($0, mint: mint, at: pin) }
        let amounts = parts.compactMap { $0 }
        guard amounts.count == parts.count else {
            showTooSmallToSplitError(total: enteredTotal)
            return .failed
        }

        switch session.hasSufficientFunds(for: total) {
        case .insufficient(let shortfall):
            if let shortfall { showYoureShortError(amount: shortfall) } else { showInsufficientBalanceError() }
            return .failed
        case .sufficient:
            break
        }
        // On a bonding curve the parts can price to more quarks than the whole; the sender pays the parts.
        let spentQuarks = amounts.reduce(UInt64(0)) { $0 + $1.onChainAmount.quarks }
        guard spentQuarks <= session.balance(for: mint)?.quarks ?? 0 else {
            showInsufficientBalanceError()
            return .failed
        }

        let sendLimit = session.sendLimitFor(currency: total.nativeAmount.currency) ?? .zero
        guard total.nativeAmount.value <= sendLimit.nextTransaction.value else {
            showLimitsError()
            return .failed
        }

        var payments: [(amount: ExchangedFiat, recipientOwner: PublicKey)] = []
        for (userID, amount) in zip(selection, amounts) {
            do {
                payments.append((amount, try await resolver.resolveUserID(userID)))
            } catch {
                showSendError()
                return .failed
            }
        }

        let chat = ChatPaymentMetadata.groupPayment(chatID: conversationID)
        do {
            if payments.count == 1, let payment = payments.first {
                try await sender.send(amount: payment.amount, verifiedState: pin, to: payment.recipientOwner, chat: chat)
            } else {
                try await multiSender.sendMultiple(payments, verifiedState: pin, chat: chat)
            }
            Analytics.transfer(event: .sentCash, exchangedFiat: total, grabTime: nil, successful: true, error: nil)
            return .success
        } catch {
            Analytics.transfer(event: .sentCash, exchangedFiat: total, grabTime: nil, successful: false, error: error)
            if !(error is CancellationError) {
                showSendError()
            }
            return .failed
        }
    }

    // MARK: - Errors -

    private func presentDeposit() {
        depositMint = selectedBalance?.stored.mint
    }

    // Placeholder copy: the design has no frame for this alert yet.
    private func showTooSmallToSplitError(total: FiatAmount) {
        session.dialogItem = .error(
            title: "Amount Too Small",
            subtitle: "\(total.formatted()) is too small to split between \(selection.count) people. Pick fewer people or enter a higher amount"
        )
    }

    private func showInsufficientBalanceError() {
        session.dialogItem = .error(
            title: "You Need More Cash",
            subtitle: "Please add more cash, or try again with a lower amount"
        ) {
            .destructive("Add More Cash") { [weak self] in
                self?.presentDeposit()
            };
            .dismiss(kind: .subtle)
        }
    }

    private func showYoureShortError(amount: ExchangedFiat) {
        session.dialogItem = .error(
            title: "You're \(amount.nativeAmount.formatted()) Short",
            subtitle: "Add more cash, or try again with a lower amount"
        ) {
            .destructive("Add More Cash") { [weak self] in
                self?.presentDeposit()
            };
            .dismiss(kind: .subtle)
        }
    }

    private func showLimitsError() {
        session.dialogItem = .error(
            title: "Transaction Limit Reached",
            subtitle: "Flipcash is designed for small, every day transactions. Send limits reset daily"
        )
    }

    private func showSendError() {
        session.dialogItem = .error(
            title: "Couldn't Send",
            subtitle: "We couldn't complete the transfer. Please try again."
        )
    }
}
