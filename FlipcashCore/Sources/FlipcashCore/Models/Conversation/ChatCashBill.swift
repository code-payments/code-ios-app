//
//  ChatCashBill.swift
//  FlipcashCore
//

import Foundation

extension ConversationMessage {

    /// What `selfUserID` was paid by this `.cash` message, in the currency and mint the message
    /// carries; `nil` for non-cash content, the user's own sends, and a group send that does not
    /// list them.
    ///
    /// Same rule as Android's `receivedBy`: a group send pays only the members it lists, each their
    /// own part (never the total); a single-receiver send pays that receiver; a message with no
    /// receiver on record is a DM payment, which pays the one other person in full.
    public func cashReceived(by selfUserID: UserID) -> ExchangedFiat? {
        guard case .cash(let total) = content, !isFromSelf(selfUserID) else { return nil }

        if !cashPayments.isEmpty {
            guard let part = cashPayments.first(where: { $0.receiverID == selfUserID }),
                  let nativeValue = Decimal(string: "\(part.nativeAmount)")
            else { return nil }
            return ExchangedFiat(
                onChainAmount: TokenAmount(quarks: part.quarks, mint: total.mint),
                nativeAmount: FiatAmount(value: nativeValue, currency: total.nativeAmount.currency),
                currencyRate: total.currencyRate
            )
        }
        if let cashReceiverID {
            return cashReceiverID == selfUserID ? total : nil
        }
        return total
    }
}

/// Whether a payment that arrived in a chat earns the received bill over it.
public enum ChatCashBill {

    /// How the message reached the client. Only a live stream event can show a bill; a catch-up
    /// batch, delta, history page or initial load is replayed history.
    public enum Source: Equatable, Sendable {
        case live
        case catchUp
    }

    /// The decision's inputs, gathered by the caller at the moment the message lands.
    public struct Context: Sendable {
        public var source: Source
        public var selfUserID: UserID
        /// The conversation the message belongs to.
        public var messageConversationID: ConversationID
        /// The conversation on screen in the foreground, if any.
        public var openConversationID: ConversationID?
        /// The newest message id the store held before this batch landed. A message at or below
        /// it is a re-delivery of one already seen.
        public var countedThrough: MessageID?
        public var flagEnabled: Bool
        /// A sheet, media viewer, dialog or another bill is over the chat, or the chat itself sits
        /// in a sheet.
        public var somethingOnTop: Bool
        /// A chat bill is showing or still being prepared.
        public var billBusy: Bool

        public init(
            source: Source,
            selfUserID: UserID,
            messageConversationID: ConversationID,
            openConversationID: ConversationID?,
            countedThrough: MessageID?,
            flagEnabled: Bool,
            somethingOnTop: Bool,
            billBusy: Bool
        ) {
            self.source = source
            self.selfUserID = selfUserID
            self.messageConversationID = messageConversationID
            self.openConversationID = openConversationID
            self.countedThrough = countedThrough
            self.flagEnabled = flagEnabled
            self.somethingOnTop = somethingOnTop
            self.billBusy = billBusy
        }
    }

    /// The amount to show on the bill (the user's share), or `nil` when no bill should show. A
    /// dropped payment is not queued: its bubble is in the transcript and that is all it gets.
    public static func billAmount(for message: ConversationMessage, in context: Context) -> ExchangedFiat? {
        guard context.flagEnabled,
              context.source == .live,
              context.openConversationID == context.messageConversationID,
              !context.somethingOnTop,
              !context.billBusy
        else { return nil }
        if let countedThrough = context.countedThrough, message.id <= countedThrough { return nil }
        return message.cashReceived(by: context.selfUserID)
    }
}
