//
//  ReactionBoostViewModel.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The reaction state a boost reads and records around its payment.
protocol ReactionBoostReacting: AnyObject {
    func selfBoostCents(_ emoji: String, messageID: MessageID, in conversationID: ConversationID) -> UInt64
    func recordOwnBoost(_ emoji: String, selfTotalCents: UInt64, messageID: MessageID, in conversationID: ConversationID)
}

extension ConversationReactions: ReactionBoostReacting {}

/// The message a boost is for: where it is, who wrote it, and what kind of chat it is in.
struct ReactionBoostTarget: Hashable, Identifiable {
    let conversationID: ConversationID
    let messageID: MessageID
    let messageSender: UserID
    let chat: ReactionBoostSplit.Chat
    /// The conversation's type, for analytics only. Nil when it isn't known locally.
    var conversationType: ConversationType?

    var id: Self { self }
}

/// Boosts one of the user's existing reactions on a message: pays its one or two payees in USD at one
/// verified rate. The reaction itself is never added or removed here.
@Observable
final class ReactionBoostViewModel {

    /// Result of a boost attempt. `.success` dismisses the sheet; `.failed` keeps it open. Error copy is
    /// surfaced through `session.dialogItem`.
    enum Outcome: Equatable {
        case success
        case failed
    }

    enum Error: Swift.Error {
        case noSpendableBalance
    }

    /// The preset amounts, in USD cents.
    static let presetCents: [UInt64] = [100, 500, 1000]

    /// The amount picked, in USD cents.
    var selectedCents: UInt64?

    var depositMint: PublicKey?

    private(set) var selectedBalance: ExchangedBalance?

    let target: ReactionBoostTarget

    /// The user's reactions on the message, most recent first; kept current by the sheet.
    private(set) var selfReactions: [String] = []

    private var chosenEmoji: String?

    /// The reaction being boosted: the one the user cycled to, or their most recent while that one stands.
    var emoji: String? {
        if let chosenEmoji, selfReactions.contains(chosenEmoji) { return chosenEmoji }
        return selfReactions.first
    }

    /// Whether tapping the emoji has another reaction to move to.
    var canCycleEmoji: Bool { selfReactions.count > 1 }

    @ObservationIgnored let session: Session
    @ObservationIgnored let ratesController: RatesController
    @ObservationIgnored let sender: any DirectSending
    @ObservationIgnored let multiSender: any MultiSending
    @ObservationIgnored let resolver: any RecipientResolving
    @ObservationIgnored let reactions: any ReactionBoostReacting
    @ObservationIgnored private let payer: UserID

    /// The smallest amount this user can boost the message with, in cents; nil when it is their own.
    var minimumCents: UInt64? {
        ReactionBoostSplit.minimumCents(payer: payer, messageSender: target.messageSender, chat: target.chat)
    }

    /// Who receives the boost, worded for the sheet: all of it to the other person in a DM, the 80/20 split
    /// in a group, or all of it to the author when the host is one of the two.
    var splitDescription: String {
        switch target.chat {
        case .dm:
            return "100% goes to them"
        case .group(let creator):
            if payer != creator && target.messageSender != creator {
                return "80% goes to the person who wrote the message, 20% goes to the group host"
            }
            return "100% goes to the person who wrote the message"
        }
    }

    var canSubmit: Bool {
        guard emoji != nil, let selectedCents, let minimumCents else { return false }
        return selectedCents >= minimumCents
    }

    init(
        sessionContainer: SessionContainer,
        target: ReactionBoostTarget,
        selfReactions: [SelfReaction],
        sender: (any DirectSending)? = nil,
        multiSender: (any MultiSending)? = nil,
        resolver: (any RecipientResolving)? = nil,
        reactions: (any ReactionBoostReacting)? = nil
    ) {
        let session = sessionContainer.session
        let ratesController = sessionContainer.ratesController
        self.session = session
        self.ratesController = ratesController
        self.target = target
        self.payer = session.userID
        self.sender = sender ?? session
        self.multiSender = multiSender ?? session
        self.resolver = resolver ?? session
        self.reactions = reactions ?? sessionContainer.conversationController.reactions
        self.selectedBalance = ratesController.resolveInitialBalance(mint: nil, session: session)
        updateSelfReactions(selfReactions)
    }

    /// Takes the user's current reactions on the message; a boosted one that was removed drops out.
    func updateSelfReactions(_ reactions: [SelfReaction]) {
        selfReactions = reactions
            .sorted { ($0.reactedAt, $0.emoji) > ($1.reactedAt, $1.emoji) }
            .map(\.emoji)
    }

    /// Moves to the user's next reaction on the message, wrapping after the oldest.
    func cycleEmoji() {
        guard canCycleEmoji, let emoji, let index = selfReactions.firstIndex(of: emoji) else { return }
        chosenEmoji = selfReactions[(index + 1) % selfReactions.count]
    }

    /// The balances the "Pay with" picker offers.
    var paymentOptions: [ExchangedBalance] {
        session.balances(for: ratesController.rateForBalanceCurrency()).giveable()
    }

    func selectCurrencyAction(exchangedBalance: ExchangedBalance) {
        selectedBalance = exchangedBalance
        ratesController.selectToken(exchangedBalance.stored.mint, source: .user)
    }

    // MARK: - Submit -

    /// Pays the selected amount as a boost on the shown reaction.
    func submit() async -> Outcome {
        guard let cents = selectedCents, let emoji else { return .failed }

        let split: ReactionBoostSplit
        do {
            split = try ReactionBoostSplit.split(
                totalCents: cents,
                payer: payer,
                messageSender: target.messageSender,
                chat: target.chat
            )
        } catch {
            switch error {
            case .selfBoost:
                return .failed
            case .shareBelowMinimum:
                showBelowMinimumError()
                return .failed
            }
        }

        guard let selectedBalance else {
            ErrorReporting.captureError(
                Error.noSpendableBalance,
                reason: "No spendable balance at boost submission",
                metadata: ["emoji": emoji]
            )
            session.dialogItem = .error(
                title: "Balance Unavailable",
                subtitle: "We couldn't load your balance. Please try again."
            )
            return .failed
        }

        let mint = selectedBalance.stored.mint
        guard let pin = await ratesController.currentPinnedState(for: .usd, mint: mint),
              let total = price(cents: cents, mint: mint, pin: pin) else {
            ErrorReporting.captureError(
                RatesController.Error.exchangeRateUnavailable,
                reason: "No fresh rate at boost submission",
                metadata: ["mint": mint.base58]
            )
            session.dialogItem = .error(
                title: "Rate Unavailable",
                subtitle: "Couldn't get a fresh rate. Please try again."
            )
            return .failed
        }

        let priced = split.shares.map { share in (share, price(cents: share.cents, mint: mint, pin: pin)) }
        let shares = priced.compactMap { share, amount in amount.map { (share: share, amount: $0) } }
        guard shares.count == priced.count else {
            showBelowMinimumError()
            return .failed
        }

        switch session.hasSufficientFunds(for: total) {
        case .insufficient(let shortfall):
            if let shortfall { showYoureShortError(amount: shortfall) } else { showInsufficientBalanceError() }
            return .failed
        case .sufficient:
            break
        }
        let spentQuarks = shares.reduce(UInt64(0)) { $0 + $1.amount.onChainAmount.quarks }
        guard spentQuarks <= session.balance(for: mint)?.quarks ?? 0 else {
            showInsufficientBalanceError()
            return .failed
        }

        let sendLimit = session.sendLimitFor(currency: .usd) ?? .zero
        guard total.nativeAmount.value <= sendLimit.nextTransaction.value else {
            showLimitsError()
            return .failed
        }

        var payments: [(amount: ExchangedFiat, recipientOwner: PublicKey)] = []
        for share in shares {
            do {
                payments.append((share.amount, try await resolver.resolveUserID(share.share.userID)))
            } catch {
                showSendError()
                return .failed
            }
        }

        let previousCents = reactions.selfBoostCents(emoji, messageID: target.messageID, in: target.conversationID)
        let chat = ChatPaymentMetadata.reactionBoost(chatID: target.conversationID, messageID: target.messageID, emoji: emoji)
        do {
            if payments.count == 1, let payment = payments.first {
                try await sender.send(amount: payment.amount, verifiedState: pin, to: payment.recipientOwner, chat: chat)
            } else {
                try await multiSender.sendMultiple(payments, verifiedState: pin, chat: chat)
            }
        } catch {
            Analytics.sentBoost(chatType: target.conversationType, exchangedFiat: total, error: error)
            if !(error is CancellationError) {
                showSendError()
            }
            return .failed
        }

        reactions.recordOwnBoost(
            emoji,
            selfTotalCents: previousCents + cents,
            messageID: target.messageID,
            in: target.conversationID
        )
        Analytics.sentBoost(chatType: target.conversationType, exchangedFiat: total, error: nil)
        return .success
    }

    /// `cents` of USD in `mint` at the pinned rate, or nil when it can't be priced.
    private func price(cents: UInt64, mint: PublicKey, pin: VerifiedState) -> ExchangedFiat? {
        session.price(FiatAmount(value: Decimal(cents) / 100, currency: pin.rate.currency), mint: mint, at: pin)
    }

    // MARK: - Errors -

    private func presentDeposit() {
        depositMint = selectedBalance?.stored.mint
    }

    private func showBelowMinimumError() {
        let minimum = ratesController.displayCurrency.amount(
            .usd(Decimal(minimumCents ?? ReactionBoostSplit.minimumShareCents) / 100)
        )
        session.dialogItem = .error(
            title: "Amount Too Small",
            subtitle: "Paid reactions start at \(minimum.formatted())"
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
            title: "You're \(ratesController.displayCurrency.amount(amount).formatted()) Short",
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
            title: "Couldn't Pay",
            subtitle: "We couldn't complete the payment. Please try again."
        )
    }
}
