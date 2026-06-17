//
//  ConversationMessageRow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Bubble styling shared by text and cash messages, from the "Message UI"
/// Figma. The corner that adjoins a grouped neighbour tightens to
/// `groupedRadius`, but only on the bubble's *aligned* edge — trailing for
/// sent, leading for received — since that's the edge consecutive bubbles
/// share. The outer edge stays fully rounded.
nonisolated enum ConversationBubbleStyle {

    /// Fill behind sent bubbles and cash cards: a light wash over the charcoal
    /// background (design 6.png measures white @ 8%). Received bubbles sit
    /// lower-contrast at white @ 2%.
    static let sentFill = Color.white.opacity(0.08)
    static let receivedFill = Color.white.opacity(0.02)
    /// Hairline border on every bubble.
    static let stroke = Color.white.opacity(0.03)
    /// Secondary labels in the transcript: card captions, token names, and
    /// date headers (white @ 50%).
    static let secondaryText = Color.white.opacity(0.5)

    static func fill(isFromSelf: Bool) -> Color {
        isFromSelf ? sentFill : receivedFill
    }

    static let baseRadius: CGFloat = 12
    static let groupedRadius: CGFloat = 6

    /// Largest a text bubble may grow before wrapping (keeps it off the
    /// opposite edge, ~75% of the screen).
    static let textMaxWidth: CGFloat = 290
    static let cashSize = CGSize(width: 232, height: 170)

    static let amountFont: Font = .default(size: 38, weight: .bold)

    static func cornerRadii(isFromSelf: Bool, groupedAbove: Bool, groupedBelow: Bool) -> RectangleCornerRadii {
        let top = groupedAbove ? groupedRadius : baseRadius
        let bottom = groupedBelow ? groupedRadius : baseRadius
        if isFromSelf {
            return RectangleCornerRadii(topLeading: baseRadius, bottomLeading: baseRadius, bottomTrailing: bottom, topTrailing: top)
        } else {
            return RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: baseRadius, topTrailing: baseRadius)
        }
    }
}

/// The bubble's fill + hairline border, drawn as explicit shape views so the
/// corner radii interpolate when grouping changes (the `in:` form snaps).
private struct ConversationBubbleChrome: ViewModifier {

    let isFromSelf: Bool
    let groupedAbove: Bool
    let groupedBelow: Bool

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: ConversationBubbleStyle.cornerRadii(
                isFromSelf: isFromSelf,
                groupedAbove: groupedAbove,
                groupedBelow: groupedBelow
            ),
            style: .continuous
        )
    }

    func body(content: Content) -> some View {
        content
            .background { shape.fill(ConversationBubbleStyle.fill(isFromSelf: isFromSelf)) }
            .overlay { shape.strokeBorder(ConversationBubbleStyle.stroke, lineWidth: 1) }
    }
}

extension View {
    fileprivate func bubbleChrome(isFromSelf: Bool, groupedAbove: Bool, groupedBelow: Bool) -> some View {
        modifier(ConversationBubbleChrome(
            isFromSelf: isFromSelf,
            groupedAbove: groupedAbove,
            groupedBelow: groupedBelow
        ))
    }
}

/// A message bubble row, aligned trailing for the signed-in user and leading
/// for the counterpart. Shows a "Delivered" / "Read 3:42 PM" receipt under the
/// user's latest sent message.
struct ConversationMessageRow: View {

    let message: ConversationMessage
    let isFromSelf: Bool
    let groupedAbove: Bool
    let groupedBelow: Bool
    /// Set only on the user's latest sent message, `nil` otherwise.
    let receipt: MessageReceipt?
    let animatesAmount: Bool

    /// Bubble corner-radius morph as messages group/ungroup.
    private static let cornerSpring = Animation.spring(duration: 0.45, bounce: 0.32)

    var body: some View {
        VStack(alignment: isFromSelf ? .trailing : .leading, spacing: 6) {
            HStack(spacing: 0) {
                if isFromSelf { Spacer(minLength: 60) }

                Group {
                    switch message.content {
                    case .text(let text):
                        ConversationBubble(
                            text: text,
                            isFromSelf: isFromSelf,
                            groupedAbove: groupedAbove,
                            groupedBelow: groupedBelow
                        )
                    case .cash(let amount):
                        ConversationCashBubble(
                            amount: amount,
                            isFromSelf: isFromSelf,
                            groupedAbove: groupedAbove,
                            groupedBelow: groupedBelow,
                            animatesAmount: animatesAmount
                        )
                    }
                }
                // Morph the adjoining corner (12 ⇄ 6) when grouping changes —
                // e.g. a new message groups with this one — instead of snapping.
                .animation(Self.cornerSpring, value: [groupedAbove, groupedBelow])
                // Consume taps on the bubble so tapping a message doesn't
                // dismiss the keyboard — only the empty space around it does.
                .contentShape(Rectangle())
                .onTapGesture { }

                if !isFromSelf { Spacer(minLength: 60) }
            }

            if isFromSelf, let receipt {
                Text(receiptText(for: receipt))
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.trailing, 10)
                    // Cross-fade the text when Delivered → Read swaps in place
                    // (same view identity, so a transition wouldn't fire).
                    .contentTransition(.opacity)
                    // Animate that swap — the transcript's message-count trigger
                    // doesn't fire on a read-pointer advance.
                    .animation(.easeInOut(duration: 0.2), value: receipt)
                    // Insertion/removal of the receipt itself as the latest
                    // message changes.
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .identity
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: isFromSelf ? .trailing : .leading)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityText))
    }

    private func receiptText(for receipt: MessageReceipt) -> String {
        switch receipt {
        case .delivered:
            return "Delivered"
        case .read(let date):
            return date.map { "Read \($0.formatted(date: .omitted, time: .shortened))" } ?? "Read"
        }
    }

    private var accessibilityText: String {
        let base: String
        switch message.content {
        case .text(let text):
            base = "\(isFromSelf ? "You" : "Them"): \(text)"
        case .cash(let amount):
            base = "\(isFromSelf ? "You sent" : "You received") \(amount.nativeAmount.formatted())"
        }
        // The combined label overrides the caption child, so fold the receipt
        // in so VoiceOver announces "Read 3:42 PM".
        guard isFromSelf, let receipt else { return base }
        return "\(base), \(receiptText(for: receipt))"
    }
}

/// A text bubble: sent reads brighter, received sits lower-contrast, both
/// tightening their grouped corners on the aligned edge.
struct ConversationBubble: View {

    let text: String
    let isFromSelf: Bool
    let groupedAbove: Bool
    let groupedBelow: Bool

    var body: some View {
        Text(text)
            .font(.appTextMessage)
            .foregroundStyle(Color.textMain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .bubbleChrome(isFromSelf: isFromSelf, groupedAbove: groupedAbove, groupedBelow: groupedBelow)
            .frame(maxWidth: ConversationBubbleStyle.textMaxWidth, alignment: isFromSelf ? .trailing : .leading)
    }
}

/// The "You sent / You received" cash card: currency label top-left, flag +
/// amount centered. Created server-side when a payment intent carries chat
/// metadata — clients never send them directly.
struct ConversationCashBubble: View {

    let amount: ExchangedFiat
    let isFromSelf: Bool
    let groupedAbove: Bool
    let groupedBelow: Bool
    /// Rolls the amount in from zero with a numeric text transition. Set only
    /// for bubbles inserted into an already-mounted transcript so history
    /// renders statically.
    let animatesAmount: Bool

    @State private var showsFinalAmount = false

    @Environment(Session.self) private var session

    /// Spring for the digit roll, started after the bubble's insertion lands.
    private static let amountRollSpring = Animation.spring(duration: 0.6).delay(0.2)

    /// The token branding in the card's corner. USDF reads as plain "Cash";
    /// launchpad currencies show their name and icon when the balance
    /// metadata is cached.
    private var tokenBalance: StoredBalance? {
        guard amount.mint != .usdf else { return nil }
        return session.balance(for: amount.mint)
    }

    var body: some View {
        ZStack {
            HStack(spacing: 4) {
                if let imageURL = tokenBalance?.imageURL {
                    RemoteImage(url: imageURL)
                        .frame(width: 13, height: 13)
                        .clipShape(Circle())
                }
                Text(tokenBalance?.name ?? "Cash")
                    .font(.appTextHeading)
                    .foregroundStyle(ConversationBubbleStyle.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 11)
            .padding(.top, 8)

            VStack(spacing: 4) {
                Text(isFromSelf ? "You sent" : "You received")
                    .font(.appTextCaption)
                    .foregroundStyle(ConversationBubbleStyle.secondaryText)

                HStack(spacing: 11) {
                    Flag(style: amount.nativeAmount.currency.flagStyle, size: .regular)
                    Text(displayedAmount.formatted())
                        .font(ConversationBubbleStyle.amountFont)
                        .foregroundStyle(Color.textMain)
                        .contentTransition(.numericText(value: NSDecimalNumber(decimal: displayedAmount.value).doubleValue))
                }
            }
        }
        .frame(width: ConversationBubbleStyle.cashSize.width, height: ConversationBubbleStyle.cashSize.height)
        .bubbleChrome(isFromSelf: isFromSelf, groupedAbove: groupedAbove, groupedBelow: groupedBelow)
        .onAppear {
            guard animatesAmount, !showsFinalAmount else { return }
            withAnimation(Self.amountRollSpring) {
                showsFinalAmount = true
            }
        }
    }

    private var displayedAmount: FiatAmount {
        if animatesAmount && !showsFinalAmount {
            return FiatAmount(value: 0, currency: amount.nativeAmount.currency)
        }
        return amount.nativeAmount
    }
}

/// A centered day + time header separating runs of messages, e.g.
/// "Today 12:13 PM".
struct ConversationDateSeparator: View {

    let date: Date

    private var day: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month().day())
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(day)
                .font(.appTextHeading)
                .foregroundStyle(ConversationBubbleStyle.secondaryText)
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.appTextCaption)
                .foregroundStyle(ConversationBubbleStyle.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}
