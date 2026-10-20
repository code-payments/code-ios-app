//
//  ReactionBoostViewModel.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The reaction calls a boost makes around its payment.
protocol ReactionBoostReacting: AnyObject {
    func addForBoost(_ emoji: String, messageID: MessageID, in conversationID: ConversationID, at date: Date) async -> ConversationReactions.BoostAdd
    func toggle(_ emoji: String, messageID: MessageID, in conversationID: ConversationID, at date: Date)
    func selfBoostCents(_ emoji: String, messageID: MessageID, in conversationID: ConversationID) -> UInt64
    func recordOwnBoost(_ emoji: String, selfTotalCents: UInt64, messageID: MessageID, in conversationID: ConversationID)
}

extension ConversationReactions: ReactionBoostReacting {}

/// The message a boost is for: where it is, who wrote it, and who owns the group.
struct ReactionBoostTarget: Hashable, Identifiable {
    let conversationID: ConversationID
    let messageID: MessageID
    let emoji: String
    let messageSender: UserID
    let creator: UserID

    var id: Self { self }
}

/// Pays a paid reaction: adds the reaction, then pays its one or two payees in USD at one verified rate.
/// A payment that fails or is cancelled takes back the reaction it added.
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

    @ObservationIgnored let session: Session
    @ObservationIgnored let ratesController: RatesController
    @ObservationIgnored let sender: any DirectSending
    @ObservationIgnored let multiSender: any MultiSending
    @ObservationIgnored let resolver: any RecipientResolving
    @ObservationIgnored let reactions: any ReactionBoostReacting
    @ObservationIgnored private let payer: UserID

    /// The smallest amount this user can boost the message with, in cents; nil when it is their own.
    var minimumCents: UInt64? {
        ReactionBoostSplit.minimumCents(payer: payer, messageSender: target.messageSender, creator: target.creator)
    }

    /// Who receives the boost, worded for the sheet: the 80/20 split, or all of it to the author when the host is one of the two.
    var splitDescription: String {
        if payer != target.creator && target.messageSender != target.creator {
            "80% goes to the person who wrote the message, 20% goes to the group host"
        } else {
            "100% goes to the person who wrote the message"
        }
    }

    var canSubmit: Bool {
        guard let selectedCents, let minimumCents else { return false }
        return selectedCents >= minimumCents
    }

    init(
        sessionContainer: SessionContainer,
        target: ReactionBoostTarget,
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
    }

    func selectCurrencyAction(exchangedBalance: ExchangedBalance) {
        selectedBalance = exchangedBalance
        ratesController.selectToken(exchangedBalance.stored.mint)
    }

    // MARK: - Submit -

    /// Adds the reaction, then pays the selected amount; on a failed or cancelled payment the reaction it
    /// added is removed again.
    func submit() async -> Outcome {
        guard let cents = selectedCents else { return .failed }

        let split: ReactionBoostSplit
        do {
            split = try ReactionBoostSplit.split(
                totalCents: cents,
                payer: payer,
                messageSender: target.messageSender,
                creator: target.creator
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
                metadata: ["emoji": target.emoji]
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

        let added = await reactions.addForBoost(target.emoji, messageID: target.messageID, in: target.conversationID, at: .now)
        switch added {
        case .failed:
            return .failed
        case .added, .alreadyReacted:
            break
        }

        let previousCents = reactions.selfBoostCents(target.emoji, messageID: target.messageID, in: target.conversationID)
        let chat = ChatPaymentMetadata.reactionBoost(chatID: target.conversationID, messageID: target.messageID, emoji: target.emoji)
        do {
            if payments.count == 1, let payment = payments.first {
                try await sender.send(amount: payment.amount, verifiedState: pin, to: payment.recipientOwner, chat: chat)
            } else {
                try await multiSender.sendMultiple(payments, verifiedState: pin, chat: chat)
            }
        } catch {
            if added == .added {
                reactions.toggle(target.emoji, messageID: target.messageID, in: target.conversationID, at: .now)
            }
            if !(error is CancellationError) {
                showSendError()
            }
            return .failed
        }

        reactions.recordOwnBoost(
            target.emoji,
            selfTotalCents: previousCents + cents,
            messageID: target.messageID,
            in: target.conversationID
        )
        return .success
    }

    /// `cents` of USD in `mint` at the pinned rate, or nil when it can't be priced.
    private func price(cents: UInt64, mint: PublicKey, pin: VerifiedState) -> ExchangedFiat? {
        let usd = FiatAmount(value: Decimal(cents) / 100, currency: pin.rate.currency)
        if mint == .usdf {
            return ExchangedFiat(nativeAmount: usd, rate: pin.rate)
        }
        let balance = session.balance(for: mint)
        guard let supply = pin.supplyFromBonding else { return nil }
        return ExchangedFiat.compute(
            fromEntered: usd,
            rate: pin.rate,
            mint: mint,
            supplyQuarks: supply,
            balance: balance.map(\.usdf),
            tokenBalanceQuarks: balance?.quarks
        )
    }

    // MARK: - Errors -

    private func presentDeposit() {
        depositMint = selectedBalance?.stored.mint
    }

    private func showBelowMinimumError() {
        let minimum = FiatAmount.usd(Decimal(minimumCents ?? ReactionBoostSplit.minimumShareCents) / 100)
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
            title: "Couldn't Pay",
            subtitle: "We couldn't complete the payment. Please try again."
        )
    }
}
