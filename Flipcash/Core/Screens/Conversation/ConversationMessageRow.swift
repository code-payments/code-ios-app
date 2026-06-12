//
//  ConversationMessageRow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A message bubble in the transcript, aligned trailing for the signed-in user
/// and leading for the counterpart. The timestamp shows only on the last bubble
/// of a same-sender run.
struct ConversationMessageRow: View {

    let message: ConversationMessage
    let isFromSelf: Bool
    let showsTimestamp: Bool

    var body: some View {
        HStack(spacing: 0) {
            if isFromSelf { Spacer(minLength: 40) }

            VStack(alignment: isFromSelf ? .trailing : .leading, spacing: 2) {
                switch message.content {
                case .text(let text):
                    ConversationBubble(text: text, isFromSelf: isFromSelf)
                case .cash(let amount):
                    ConversationCashBubble(amount: amount, isFromSelf: isFromSelf)
                }
                if showsTimestamp {
                    Text(message.date, format: .dateTime.hour().minute())
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 4)
                }
            }

            if !isFromSelf { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(isFromSelf ? "You" : "Them"): \(accessibilityText)"))
    }

    private var accessibilityText: String {
        switch message.content {
        case .text(let text): text
        case .cash(let amount): "\(amount.nativeAmount.formatted()) cash"
        }
    }
}

/// A single rounded-rectangle conversation bubble. Sent bubbles read brighter; received
/// bubbles sit lower-contrast — distinguished by shade and alignment.
struct ConversationBubble: View {

    let text: String
    let isFromSelf: Bool

    var body: some View {
        Text(text)
            .font(.appTextMessage)
            .foregroundStyle(Color.textMain)
            .padding(.vertical, 9)
            .padding(.horizontal, 13)
            .background(
                isFromSelf ? Color.white.opacity(0.18) : Color.white.opacity(0.07),
                in: .rect(cornerRadius: 20)
            )
    }
}

/// A cash-payment bubble: the transferred amount over a "Cash" caption. Uses
/// the same shade pairing as text bubbles so direction stays readable.
struct ConversationCashBubble: View {

    let amount: ExchangedFiat
    let isFromSelf: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Cash")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            Text(amount.nativeAmount.formatted())
                .font(.appTextMessage)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textMain)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 13)
        .background(
            isFromSelf ? Color.white.opacity(0.18) : Color.white.opacity(0.07),
            in: .rect(cornerRadius: 20)
        )
    }
}

/// A centered date/time header separating runs of messages.
struct ConversationDateSeparator: View {

    let date: Date

    private var label: String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday \(time)" }
        return "\(date.formatted(.dateTime.month().day())) \(time)"
    }

    var body: some View {
        Text(label)
            .font(.appTextSmall)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
    }
}
