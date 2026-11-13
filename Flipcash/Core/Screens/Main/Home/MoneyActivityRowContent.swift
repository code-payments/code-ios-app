//
//  MoneyActivityRowContent.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// A Recent Activity row on the Money screen (node 13729:744): the group a payment
/// moved in when the server says which one, and who and when underneath.
enum MoneyActivityRowContent {

    /// The conversation an activity happened in. Only boosts, requested payments
    /// and returned payments carry one; nothing else says.
    static func conversationID(
        boostedReaction: Activity.BoostedReaction?,
        requestedPayment: Activity.RequestedPayment?,
        returnedPayment: Activity.ReturnedPayment?
    ) -> ConversationID? {
        boostedReaction?.conversationID
            ?? requestedPayment?.conversationID
            ?? returnedPayment?.conversationID
    }

    /// The group's name when there is one, otherwise today's row title.
    static func title(groupName: String?, fallback: String) -> String {
        guard let groupName, !groupName.isEmpty else { return fallback }
        return groupName
    }

    /// "Joe Payne · Today", or the day alone when there is no name.
    static func subtitle(name: String?, day: String) -> String {
        guard let name, !name.isEmpty else { return day }
        return "\(name) · \(day)"
    }

    /// The day an activity happened: "Today", "Yesterday", then a weekday or date.
    static func dayText(for date: Date) -> String {
        date.formattedRelatively()
    }

    /// The amount as today's row shows it: signed for money in or out.
    static func amountText(_ amount: FiatAmount, signPrefix: String?) -> String {
        amount.formatted(signPrefix: signPrefix)
    }
}
