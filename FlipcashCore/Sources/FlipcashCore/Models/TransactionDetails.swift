//
//  TransactionDetails.swift
//  FlipcashCore
//

import Foundation

/// What an activity entry *was*, as the details screen states it (Figma node
/// 9708:118186).
///
/// The feed's own row title is server-authored prose ("Tipped", "Purchased",
/// "{0} sent you"): it reads fine inline but can't carry a screen. The details
/// screen states the kind in the user's own voice instead, derived from the
/// entry's kind and counterparty — the only structured signal the client gets.
///
/// The three cash kinds are distinct because the feed distinguishes them and a
/// user would too. ``gaveCash`` and ``receivedCash`` are a hand-to-hand
/// exchange — a send or a receive carrying neither a user id nor a phone number,
/// so there is nobody to name. ``sentCashLink`` is money sitting in a gift-card
/// vault until somebody opens the link, which is why it is the only kind that
/// can still be cancelled. There is no received-cash-link counterpart, because
/// collecting one is indistinguishable in the feed from taking a bill in
/// person — both arrive as an unattributed receive.
public enum TransactionKind: String, Sendable, Equatable, Hashable, CaseIterable {

    case tipped
    case received
    case sent
    case gaveCash
    case receivedCash
    case sentCashLink
    case buy
    case sell
    case withdraw
    case deposit
    case convert
    case poolPayment
    case unknown

    /// How the screen titles the entry when there is no counterparty to name it with.
    public var heading: String {
        switch self {
        case .tipped:       "You tipped"
        case .received:     "You received"
        case .sent:         "You sent"
        case .gaveCash:     "You gave cash"
        case .receivedCash: "You received cash"
        case .sentCashLink: "You sent a cash link"
        case .buy:          "Buy"
        case .sell:         "Sell"
        case .withdraw:     "Withdraw"
        case .deposit:      "Deposit"
        case .convert:      "Convert"
        case .poolPayment:  "Pool payment"
        case .unknown:      "Transaction"
        }
    }
}

/// An entry's settlement state, as the details screen's Status row phrases it.
public enum TransactionStatus: String, Sendable, Equatable, Hashable, CaseIterable {

    case pending
    case completed
    case failed
    case unknown

    public var label: String {
        switch self {
        case .pending:   "Pending"
        case .completed: "Completed"
        case .failed:    "Failed"
        case .unknown:   "Unknown"
        }
    }
}

/// Everything the transaction details screen draws, resolved from the activity
/// the user tapped (Figma node 9708:105260).
///
/// Reads the same entry the activity row reads, through the same helpers
/// (``Activity/Kind/signPrefix``, ``Activity/isTipVerb(_:)``,
/// ``conversionTitle(from:to:)``), so a row and the screen it opens can never
/// disagree about what the entry was. What it adds is everything a row has no
/// space for: the kind stated in the user's own voice, the receipt values, and
/// the actions.
///
/// Pure and synchronous: the counterparty's name and the two token names arrive
/// already resolved, so an unresolved one simply fills in when it lands.
public struct TransactionDetails: Sendable, Equatable, Hashable {

    /// The entry's id, base58-encoded — what the copy control puts on the
    /// clipboard, and the value someone pastes into a support ticket.
    public let id: String

    public let kind: TransactionKind

    /// What the screen is titled when the entry has something better to say than
    /// its ``kind`` — the person-to-person case: a tip, a send and a receive are
    /// all headed by the counterparty's display name, and the +/- on the amount
    /// is what states the direction. `nil` falls back to the kind's own heading,
    /// which is also what an unresolved counterparty gets: "You tipped" beats a
    /// blank line.
    public let heading: String?

    /// The other side of the movement, under the heading — "In Person" for cash
    /// handed over, "Dollars → Jeffy" for a conversion. `nil` wherever the header
    /// already says everything: a person entry, whose name is the ``heading``,
    /// and a cash link, whose own heading names it.
    public let subtitle: String?

    /// The direction marker the amount carries, matching the activity row's.
    public let signPrefix: String?

    /// The entry's amount, as the feed settled it.
    public let amount: ExchangedFiat

    public let date: Date
    public let status: TransactionStatus

    /// What the movement cost. Conversions only.
    public let fee: FiatAmount?

    /// A conversion's destination amount, `nil` while the swap is still pending —
    /// which is exactly when the receipt row is left out rather than shown as zero.
    public let received: FiatAmount?

    /// Whether the movement can still be pulled back — an open cash link, and
    /// nothing else.
    public let canCancel: Bool

    /// Whether the counterparty's conversation can be opened from here.
    public let canViewInChat: Bool

    /// The line the header actually renders.
    public var title: String { heading ?? kind.heading }

    /// The currency the entry was denominated in — the receipt's Currency row.
    public var currency: CurrencyCode { amount.nativeAmount.currency }

    /// The rate the entry settled at — the receipt's Exchange Rate row.
    public var exchangeRate: Decimal { amount.currencyRate.fx }

    /// What moved on-chain — the receipt's Tokens row. Unlike Android, this is
    /// the quantity the feed recorded rather than one re-estimated from the
    /// mint's current supply, because the iOS feed carries `onChainAmount`.
    public var tokenAmount: TokenAmount { amount.onChainAmount }
}

// MARK: - Mapping -

extension TransactionDetails {

    /// Resolves an activity into the details screen's state.
    ///
    /// - Parameters:
    ///   - counterpartyName: the other party's display name, once it resolves.
    ///   - fromTokenName: the entry's mint name, used by a conversion's subtitle.
    ///   - toTokenName: a conversion's destination mint name.
    public init(
        activity: Activity,
        counterpartyName: String? = nil,
        fromTokenName: String? = nil,
        toTokenName: String? = nil,
    ) {
        let kind = TransactionKind(activity: activity)
        let swap = activity.swapMetadata

        self.id = activity.id.base58
        self.kind = kind
        self.heading = counterpartyName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        self.subtitle = Self.subtitle(kind: kind, fromTokenName: fromTokenName, toTokenName: toTokenName)
        self.signPrefix = activity.kind.signPrefix
        self.amount = activity.exchangedFiat
        self.date = activity.date
        self.status = TransactionStatus(activity: activity)
        self.fee = swap?.fee
        self.received = swap?.toFiat
        self.canCancel = activity.cancellableCashLinkMetadata != nil
        // Opening the conversation needs somebody to open it with, and only a
        // user id identifies one — a phone-number counterparty has no chat. The
        // display name is not required: the chat screen derives its own header
        // from the id (see `AppRouter.Destination.tipConversationForUser`).
        self.canViewInChat = activity.counterparty?.userID != nil
    }

    /// The other side of the movement, for the kinds whose heading doesn't
    /// already carry it. `nil` wherever the header already says everything, and
    /// wherever the feed can't answer it: a buy or a sell records only the mint
    /// that moved, and a withdrawal or deposit's other side is an address the
    /// feed doesn't carry.
    private static func subtitle(kind: TransactionKind, fromTokenName: String?, toTokenName: String?) -> String? {
        switch kind {
        case .gaveCash, .receivedCash:
            return "In Person"
        case .convert:
            return conversionTitle(from: fromTokenName, to: toTokenName)
        case .tipped, .received, .sent, .sentCashLink, .buy, .sell,
             .withdraw, .deposit, .poolPayment, .unknown:
            return nil
        }
    }

    /// The "<from> → <to>" pair a conversion is named by, or `nil` when either
    /// leg's token name is still unresolved — a half-empty pair says less than
    /// the server-rendered title it would replace.
    ///
    /// Shared with the activity row's own conversion title so the row and the
    /// screen it opens read alike.
    public static func conversionTitle(from: String?, to: String?) -> String? {
        guard
            let from = from?.nilIfEmpty,
            let to = to?.nilIfEmpty
        else { return nil }
        return "\(from) \u{2192} \(to)"
    }
}

// MARK: - Kind -

extension TransactionKind {

    /// What the entry was, from the kind and counterparty the feed carries.
    ///
    /// The two hand-to-hand kinds are the send/receive pair with no counterparty
    /// at all — a bill hand-off never exchanges identities, so there is genuinely
    /// nobody to name. The server's verb separates a tip from a plain send, which
    /// the kind alone doesn't; see ``Activity/isTipVerb(_:)``.
    init(activity: Activity) {
        switch activity.kind {
        case .gave:
            if activity.counterparty == nil {
                self = .gaveCash
            } else {
                self = Activity.isTipVerb(activity.title) ? .tipped : .sent
            }
        case .received:
            self = activity.counterparty == nil ? .receivedCash : .received
        case .cashLink:  self = .sentCashLink
        case .bought:    self = .buy
        case .sold:      self = .sell
        case .withdrew:  self = .withdraw
        case .deposited: self = .deposit
        case .swapped:   self = .convert
        case .paid:      self = .poolPayment
        // Neither `paid` nor `distributed` is produced by the current activity
        // contract; both are legacy kinds that survive in old local rows.
        // `paid` has a heading of its own above; a distribution has none to
        // borrow, so it falls back rather than claiming a movement it isn't.
        case .distributed, .unknown:
            self = .unknown
        }
    }
}

// MARK: - Status -

extension TransactionStatus {

    /// The settlement state the Status row reads out.
    ///
    /// A conversion is settled by its swap, not by the notification: the entry
    /// itself completes as soon as the source side is debited, so a failed swap
    /// would otherwise read "Completed".
    init(activity: Activity) {
        if let swap = activity.swapMetadata {
            switch swap.state {
            case .failed:
                self = .failed
                return
            case .pending:
                self = .pending
                return
            case .unknown, .succeeded, .none:
                break
            }
        }

        switch activity.state {
        case .pending:   self = .pending
        case .completed: self = .completed
        case .unknown:   self = .unknown
        }
    }
}

// MARK: - Shared Readings -

extension Activity {

    /// Whether a server-rendered activity title uses the tip verb.
    ///
    /// The backend picks the verb from the payment's location, so a tip-card tip
    /// arrives titled "Tipped" and an in-chat send "Sent"; `activity/v1` models
    /// both as plain sent crypto with no structured tip flag, so there is no
    /// other signal to read. Matching the verb is safe while the feed's titles
    /// are English-only.
    public static func isTipVerb(_ title: String) -> Bool {
        title
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .hasPrefix("tip")
    }
}

extension Activity.Kind {

    /// The sign an amount of this kind carries, so a debit reads as one wherever
    /// it is shown, or `nil` for a kind that renders unsigned.
    public var signPrefix: String? {
        switch self {
        case .received, .deposited, .bought, .distributed, .sold:
            return "+"
        case .gave, .withdrew, .cashLink, .paid:
            return "-"
        case .swapped, .unknown:
            // A swap's net effect on the wallet isn't inherently in or out, so it
            // renders unsigned until the swap notification is modelled richly.
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
