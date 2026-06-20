//
//  ChatItem+Conversation.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashUI

extension ChatItem {

    /// Maps a conversation's messages to display-ready transcript items: resolves sender side,
    /// formats cash amounts, derives the currency flag, inserts a date separator before the first
    /// message and whenever a gap longer than `gap` opens, and computes same-sender grouping the
    /// way the transcript does. Pure — `cashBranding` supplies the token name + launchpad icon so
    /// this stays testable; it defaults to plain "Cash" (USDF), and the screen injects bonded-mint
    /// branding from `Session`.
    static func from(
        _ messages: [ConversationMessage],
        selfUserID: UserID,
        gap: TimeInterval = 15 * 60,
        counterpartRead: (pointer: MessageID, date: Date?)? = nil,
        cashBranding: (ExchangedFiat) -> (token: String, iconURL: URL?) = { _ in ("Cash", nil) }
    ) -> [ChatItem] {
        // Only the user's latest sent message carries a receipt.
        let latestFromSelfID = messages.last { $0.senderID == selfUserID }?.id
        var items: [ChatItem] = []
        for (index, message) in messages.enumerated() {
            let isFromSelf = message.senderID == selfUserID
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil

            // A separator opens the transcript and breaks any run longer than the gap.
            let showsSeparator = previous.map { message.date.timeIntervalSince($0.date) > gap } ?? true
            if showsSeparator {
                items.append(.dateSeparator(id: "sep-\(message.id.value)", text: Self.separatorText(for: message.date)))
            }

            let groupedAbove = previous.map {
                ($0.senderID == selfUserID) == isFromSelf && message.date.timeIntervalSince($0.date) <= gap
            } ?? false
            let groupedBelow = next.map {
                ($0.senderID == selfUserID) == isFromSelf && $0.date.timeIntervalSince(message.date) <= gap
            } ?? false

            let content: ChatMessage.Content
            switch message.content {
            case .text(let text):
                content = .text(text)
            case .cash(let fiat):
                let currency = fiat.nativeAmount.currency
                let flagName = currency.region?.rawValue ?? currency.rawValue.uppercased()
                let branding = cashBranding(fiat)
                content = .cash(ChatCashContent(
                    amount: fiat.nativeAmount.formatted(),
                    token: branding.token,
                    flagImageName: flagName,
                    iconURL: branding.iconURL
                ))
            }

            items.append(.message(ChatMessage(
                id: "\(message.id.value)",
                content: content,
                sender: isFromSelf ? .me : .other,
                isContinuationFromPrevious: groupedAbove,
                isContinuedByNext: groupedBelow
            )))

            if isFromSelf, message.id == latestFromSelfID {
                items.append(.receipt(
                    id: "receipt-\(message.id.value)",
                    text: Self.receiptText(for: message.id, counterpartRead: counterpartRead)
                ))
            }
        }
        return items
    }

    /// "Read 3:42 PM" once the counterpart's read pointer reaches the message, else "Delivered".
    private static func receiptText(for messageID: MessageID, counterpartRead: (pointer: MessageID, date: Date?)?) -> String {
        guard let read = counterpartRead, read.pointer >= messageID else { return "Delivered" }
        guard let date = read.date else { return "Read" }
        return "Read \(date.formattedTime())"
    }

    /// "Today 12:13 PM" / "Yesterday 9:05 AM" / "Jun 18 4:30 PM".
    private static func separatorText(for date: Date) -> String {
        let day: String
        if Calendar.current.isDateInToday(date) {
            day = "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            day = "Yesterday"
        } else {
            day = date.formatted(.dateTime.month().day())
        }
        return "\(day) \(date.formattedTime())"
    }
}
