//
//  GroupSendViewModel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Sends cash into a private group: the sender enters an amount, picks up to ten members, and every
/// one of them is paid that amount, in the order they were picked. One recipient is a single payment;
/// two or more are one multi-recipient intent, every payment priced at one verified state.
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

    /// The most people one send can pay.
    static let maxRecipients = 10

    /// Who is checked, in the order they were checked; that is the order of the payments.
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

    /// The amount each person gets, in the currency it was typed in.
    var enteredAmountEach: FiatAmount? {
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

    /// Checks or unchecks a member. An eleventh is refused with the "10 People Max" notice.
    func toggle(_ userID: UserID) {
        if let index = selection.firstIndex(of: userID) {
            selection.remove(at: index)
            return
        }
        guard selection.count < Self.maxRecipients else {
            session.dialogItem = .info(
                title: "10 People Max",
                subtitle: "The maximum number of people you can send to at once is 10 people"
            )
            return
        }
        selection.append(userID)
    }

    /// The amount each person gets times the people checked, in the entered currency.
    var enteredTotal: FiatAmount? {
        guard let each = enteredAmountEach, !selection.isEmpty else { return nil }
        return FiatAmount(value: each.value * Decimal(selection.count), currency: each.currency)
    }

    /// The confirm sheet's large amount, "$1.00", without the "each" that follows it for a group.
    var eachAmountLabel: String? {
        guard let each = enteredAmountEach, !selection.isEmpty else { return nil }
        return each.formatted()
    }

    /// Whether the confirm sheet's amount is one person's part, followed by "each": two or more people.
    var isSplitAcrossSelection: Bool {
        selection.count > 1
    }

    /// The confirm sheet's smaller line, "$3.00 total"; nil for one person, who gets only the amount.
    var totalLabel: String? {
        guard selection.count > 1, let total = enteredTotal else { return nil }
        return "\(total.formatted()) total"
    }

    /// The Send To button title: "Send $X" with X the total, or "Send" until someone is checked.
    var sendTitle: String {
        guard let total = enteredTotal else { return "Send" }
        return "Send \(total.formatted())"
    }

    // MARK: - Submit -

    /// Prices the amount for every member checked at one verified state, and pays them.
    func submit() async -> Outcome {
        guard let enteredAmountEach, !selection.isEmpty else { return .failed }

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
        guard let pin = await ratesController.currentPinnedState(for: enteredAmountEach.currency, mint: mint) else {
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

        let each = FiatAmount(value: enteredAmountEach.value, currency: pin.rate.currency)
        // Below the currency's minimum transfer value the amount prices to nothing; that reads as insufficient.
        guard let priced = session.price(each, mint: mint, at: pin) else {
            showInsufficientBalanceError()
            return .failed
        }
        let amounts = Array(repeating: priced, count: selection.count)

        // The sender pays the sum of the payments.
        let paidFiat = FiatAmount(value: each.value * Decimal(selection.count), currency: each.currency)
        guard let paid = session.price(paidFiat, mint: mint, at: pin) else {
            showInsufficientBalanceError()
            return .failed
        }
        switch session.hasSufficientFunds(for: paid) {
        case .insufficient:
            showInsufficientBalanceError()
            return .failed
        case .sufficient:
            break
        }
        // On a bonding curve the payments can price to more quarks than the whole; the sender pays the payments.
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

        let payments: [(amount: ExchangedFiat, recipientOwner: PublicKey)]
        do {
            let owners = try await RecipientBatch.resolveOwners(selection) { @MainActor [self] in
                try await self.resolver.resolveUserID($0)
            }
            payments = zip(amounts, owners).map { (amount: $0, recipientOwner: $1) }
        } catch {
            showSendError()
            return .failed
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
