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
        suppressReceiptFor: String? = nil,
        cashBranding: (ExchangedFiat) -> (token: String, iconURL: URL?) = { _ in ("Cash", nil) }
    ) -> [ChatItem] {
        // "Delivered"/"Read" rides the latest *confirmed* self message, so an in-flight or failed send
        // trailing it doesn't strip the receipt off the last delivered bubble. A sending row shows
        // nothing; a failed row shows its own "Not Delivered" line (each independently retryable).
        let latestSentFromSelfID = messages.last { $0.isFromSelf(selfUserID) && $0.status == .sent }?.stableID
        var items: [ChatItem] = []
        for (index, message) in messages.enumerated() {
            let isFromSelf = message.isFromSelf(selfUserID)
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil

            // A separator opens the transcript and breaks any run longer than the gap.
            let showsSeparator = previous.map { message.date.timeIntervalSince($0.date) > gap } ?? true
            if showsSeparator {
                items.append(.dateSeparator(id: "sep-\(message.stableID)", text: Self.separatorText(for: message.date)))
            }

            let groupedAbove = previous.map {
                $0.isFromSelf(selfUserID) == isFromSelf && message.date.timeIntervalSince($0.date) <= gap
            } ?? false
            let groupedBelow = next.map {
                $0.isFromSelf(selfUserID) == isFromSelf && $0.date.timeIntervalSince(message.date) <= gap
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

            // The status line rides on the bubble itself (not a separate row, so a send is a clean
            // insert). All of its copy is produced here, in one layer; the cell only styles it
            // (resting vs. red + tappable) off `isFailed`.
            let receipt: String?
            switch message.status {
            case .sent:
                // "Delivered"/"Read" rides only the latest confirmed self message — preserved even when
                // a later send is in flight or failed, and held back while the row is still settling in.
                receipt = isFromSelf && message.stableID == latestSentFromSelfID && message.stableID != suppressReceiptFor
                    ? Self.receiptText(for: message.id, counterpartRead: counterpartRead)
                    : nil
            case .sending:
                // No status line while in flight — the bubble sits there until it resolves to
                // "Delivered" or the failed state.
                receipt = nil
            case .failed:
                receipt = "Not Delivered. Tap to retry"
            }

            items.append(.message(ChatMessage(
                id: message.stableID,
                content: content,
                sender: isFromSelf ? .me : .other,
                isContinuationFromPrevious: groupedAbove,
                isContinuedByNext: groupedBelow,
                receipt: receipt,
                isFailed: message.status == .failed
            )))
        }
        return items
    }

    /// "Read 3:42 PM" / "Read Yesterday" / "Read Monday" / "Read Tue, Jun 17" once the counterpart's
    /// read pointer reaches the message, else "Delivered".
    private static func receiptText(for messageID: MessageID, counterpartRead: (pointer: MessageID, date: Date?)?) -> String {
        guard let read = counterpartRead, read.pointer >= messageID else { return "Delivered" }
        guard let date = read.date else { return "Read" }
        return "Read \(date.formattedRelatively(useTimeForToday: true))"
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
