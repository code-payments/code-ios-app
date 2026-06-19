//
//  ChatMessage+Conversation.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashUI

extension ChatMessage {

    /// Maps a conversation's messages to display-ready chat rows: resolves sender side, formats
    /// cash amounts, derives the currency flag, and computes same-sender grouping the same way the
    /// transcript does (a run is broken by a sender change or a gap longer than `gap`). Pure —
    /// `cashBranding` supplies the token name + launchpad icon so this stays testable; it defaults
    /// to plain "Cash" (USDF), and the screen injects bonded-mint branding from `Session`.
    static func from(
        _ messages: [ConversationMessage],
        selfUserID: UserID,
        gap: TimeInterval = 15 * 60,
        cashBranding: (ExchangedFiat) -> (token: String, iconURL: URL?) = { _ in ("Cash", nil) }
    ) -> [ChatMessage] {
        messages.enumerated().map { index, message in
            let isFromSelf = message.senderID == selfUserID
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil

            let groupedAbove = previous.map {
                ($0.senderID == selfUserID) == isFromSelf && message.date.timeIntervalSince($0.date) <= gap
            } ?? false
            let groupedBelow = next.map {
                ($0.senderID == selfUserID) == isFromSelf && $0.date.timeIntervalSince(message.date) <= gap
            } ?? false

            let content: Content
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

            return ChatMessage(
                id: "\(message.id.value)",
                content: content,
                sender: isFromSelf ? .me : .other,
                isContinuationFromPrevious: groupedAbove,
                isContinuedByNext: groupedBelow
            )
        }
    }
}
