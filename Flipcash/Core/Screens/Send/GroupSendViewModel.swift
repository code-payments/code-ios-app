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

    /// Who is checked, in the order they were checked; that order decides who gets a leftover unit.
    /// Holds `session.userID` when You is checked: You shares the total but is never paid.
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

    /// Whether the amount screen can move on to picking people; funds are checked on the confirm sheet.
    var canContinue: Bool {
        validatedEntered != nil
    }

    /// The balances the currency picker offers.
    var paymentOptions: [ExchangedBalance] {
        ratesController.paymentOptions(session: session)
    }

    /// Pays from `exchangedBalance` and makes it the wallet's selected token.
    func selectCurrencyAction(exchangedBalance: ExchangedBalance) {
        selectedBalance = exchangedBalance
        ratesController.selectToken(exchangedBalance.stored.mint, source: .user)
    }

    // MARK: - People -

    /// The "You" row Split Between lists before the members.
    var youRow: GroupPortrait {
        GroupPortrait(userID: session.userID, name: "You", picture: nil, isHost: false)
    }

    /// The members checked, You left out, in check order: the people who get paid.
    var payees: [UserID] {
        selection.filter { $0 != session.userID }
    }

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

    /// Checks or unchecks a member or You. An eleventh person, You included, is refused with the "10 People Max" notice.
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

    /// The entered total split between everyone checked, You included; `parts` are the ones paid.
    var split: GroupSendSplit? {
        guard let enteredTotal else { return nil }
        return try? GroupSendSplit.split(total: enteredTotal, recipients: payees.count, includesYou: includesYou)
    }

    /// Whether the sender shares the total, which the confirm sheet says even for one paid member.
    var includesYou: Bool {
        selection.contains(session.userID)
    }

    /// The per-person line for the confirm sheet, from the parts paid: "$1.00 Each", or "~$0.33 Each" when uneven, ", including You" when You shares it.
    var eachLabel: String? {
        guard let split, let enteredTotal else { return nil }
        return split.eachLabel(in: enteredTotal.currency)
    }

    /// Whether the selection can go on to confirm; a total too small to split shows the alert instead.
    func confirmSelection() -> Bool {
        guard let enteredTotal, !payees.isEmpty else { return false }
        do {
            _ = try GroupSendSplit.split(total: enteredTotal, recipients: payees.count, includesYou: includesYou)
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

    /// Splits the total, prices every part at one verified state, and pays the members checked.
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
        guard let pin = await ratesController.currentPinnedState(for: enteredTotal.currency, mint: mint) else {
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

        // What the sender pays is the parts of everyone but You, not the entered total.
        let paidFiat = FiatAmount(
            value: split.amounts(in: pin.rate.currency).reduce(Decimal(0)) { $0 + $1.value },
            currency: pin.rate.currency
        )
        guard let paid = session.price(paidFiat, mint: mint, at: pin) else {
            showSendError()
            return .failed
        }
        switch session.hasSufficientFunds(for: paid) {
        case .insufficient:
            showInsufficientBalanceError()
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

        let sendLimit = session.sendLimitFor(currency: paid.nativeAmount.currency) ?? .zero
        guard paid.nativeAmount.value <= sendLimit.nextTransaction.value else {
            showLimitsError()
            return .failed
        }

        var payments: [(amount: ExchangedFiat, recipientOwner: PublicKey)] = []
        for (userID, amount) in zip(payees, amounts) {
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
            Analytics.sentCash(exchangedFiat: paid, context: .groupSend, recipientCount: payments.count, error: nil)
            return .success
        } catch {
            Analytics.sentCash(exchangedFiat: paid, context: .groupSend, recipientCount: payments.count, error: error)
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

    // Matches Android's StartChattingPayer.presentInsufficientBalance.
    private func showInsufficientBalanceError() {
        session.dialogItem = .info(
            title: "Insufficient Balance",
            subtitle: "Add more money, or enter a smaller amount"
        ) {
            .standard("Add Money") { [weak self] in
                self?.presentDeposit()
            };
            .cancel()
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
