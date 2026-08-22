//
//  ConversationReceiptReporter.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The receive-side analytics concern, split out of `ConversationController`: which
/// delivered messages count toward the cumulative received counters, what a
/// read-pointer advance reports, and how a foreign-currency tip becomes a USD number.
///
/// Every dependency is an injectable closure, defaulting to the real `Analytics`
/// entry points, so the rules can be exercised without the Mixpanel transport (which
/// is inert in tests).
@MainActor
final class ConversationReceiptReporter {

    /// How a batch of messages reached the client. The distinction only matters when
    /// the client holds nothing for the conversation yet: a **live** delivery into an
    /// empty chat is a genuine first message and counts, while a **catch-up** into an
    /// empty chat is a cold backfill replaying the event log — counting it would
    /// permanently inflate a people property that cannot be decremented.
    enum Delivery: Equatable {
        case live
        case catchUp
    }

    /// The rate for a currency, native-per-USD, or nil when none is cached. Wired to
    /// `RatesController` by `SessionContainer`; nil-returning by default so an
    /// unwired reporter under-reports value rather than reporting it wrongly.
    var usdRate: @MainActor (CurrencyCode) -> Rate? = { _ in nil }

    private let selfUserID: UserID
    private let increment: @MainActor (Analytics.ReceivedCounter, Double) -> Void
    private let trackTipReceived: @MainActor (ConversationType?, ExchangedFiat) -> Void
    private let trackMessageReceived: @MainActor (ConversationType?) -> Void

    init(
        selfUserID: UserID,
        increment: @escaping @MainActor (Analytics.ReceivedCounter, Double) -> Void = { Analytics.increment($0, by: $1) },
        trackTipReceived: @escaping @MainActor (ConversationType?, ExchangedFiat) -> Void = { Analytics.tipReceived(chatType: $0, exchangedFiat: $1) },
        trackMessageReceived: @escaping @MainActor (ConversationType?) -> Void = { Analytics.messageReceived(chatType: $0) }
    ) {
        self.selfUserID = selfUserID
        self.increment = increment
        self.trackTipReceived = trackTipReceived
        self.trackMessageReceived = trackMessageReceived
    }

    // MARK: - Counters -

    /// Credits the cumulative received counters for the inbound messages in `messages`
    /// that sit above `countedThrough` — the newest message id already stored for the
    /// conversation, read *before* this batch was persisted.
    ///
    /// A tip increments both `Tips Received` and `Messages Received`: the message
    /// counter is a total, not a non-tip remainder.
    func countReceived(
        _ messages: [ConversationMessage],
        countedThrough: MessageID?,
        delivery: Delivery
    ) {
        // Nothing stored and nothing live: a cold backfill. Seed the watermark by
        // letting the write land, but credit nothing.
        if countedThrough == nil, delivery == .catchUp { return }

        for message in messages {
            guard isInbound(message) else { continue }
            if let countedThrough, message.id <= countedThrough { continue }

            increment(.messages, 1)

            guard message.cashAction == .tipped, case .cash(let exchanged) = message.content else { continue }
            increment(.tips, 1)

            // Chat cash arrives in the SENDER's native currency. With no cached rate we
            // count the tip but skip its value: an understated total is recoverable, a
            // wrong one is permanent and unattributable.
            guard let usd = usdValue(of: exchanged) else { continue }
            increment(.tipsValue, usd)
        }
    }

    // MARK: - Events -

    /// Reports one event per inbound message in the window a read-pointer advance just
    /// crossed. `Tip Received` and `Message Received` are mutually exclusive — a tip
    /// reports only as a tip.
    func reportRead(_ messages: [ConversationMessage], chatType: ConversationType?) {
        for message in messages {
            guard isInbound(message) else { continue }
            if message.cashAction == .tipped, case .cash(let exchanged) = message.content {
                trackTipReceived(chatType, exchanged)
            } else {
                trackMessageReceived(chatType)
            }
        }
    }

    // MARK: - Private -

    /// Anything not sent by the signed-in user, matching Android: a system message
    /// (no sender) is still something the user received.
    private func isInbound(_ message: ConversationMessage) -> Bool {
        !message.isFromSelf(selfUserID)
    }

    private func usdValue(of exchanged: ExchangedFiat) -> Double? {
        let native = exchanged.nativeAmount
        if native.currency == .usd { return native.doubleValue }
        guard let rate = usdRate(native.currency) else { return nil }
        return native.convertingToUSD(rate: rate).doubleValue
    }
}
