//
//  FakeCashCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A static, non-interactive illustration of a chat cash card, used only to
/// dress the Send sheet's contact-access empty states. Proportional to the real
/// `ChatCashCardCell` (232×170); fonts, flag, and the placeholder token row all
/// scale off `width`. The chrome constants mirror `BubbleBackgroundView`
/// (continuous radius 12, white-opacity fill + hairline border) so it reads like
/// a real bubble — including the sender/recipient fill split (`isFromSelf`).
/// Purely decorative, never carries real values.
struct FakeCashCard: View {

    let caption: String
    let amount: String
    /// Drives the fill the same way `BubbleBackgroundView.fill(isFromSelf:)`
    /// does: a sent card (self) reads lighter, a received card (other) darker.
    let isFromSelf: Bool
    let width: CGFloat

    private var fillOpacity: Double { isFromSelf ? 0.08 : 0.02 }

    /// The real card's footprint; everything scales off it.
    private static let referenceWidth: CGFloat = 232
    private static let aspectRatio: CGFloat = 232 / 170

    private var scale: CGFloat { width / Self.referenceWidth }
    private var height: CGFloat { width / Self.aspectRatio }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return shape
            .fill(Color.white.opacity(fillOpacity))
            // Opaque base matching the backdrop so overlapping cards occlude
            // cleanly instead of letting the card behind bleed through the tint.
            .background(Color.backgroundMain, in: shape)
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) { TokenPlaceholder(scale: scale) }
            .overlay { CardCenterStack(caption: caption, amount: amount, scale: scale) }
            .overlay { shape.stroke(Color.white.opacity(0.03), lineWidth: 1) }
    }
}

/// Stand-in for the real card's coin icon + token name.
private struct TokenPlaceholder: View {
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 4 * scale) {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 12 * scale, height: 12 * scale)
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 26 * scale, height: 5 * scale)
        }
        .padding(.leading, 11 * scale)
        .padding(.top, 8 * scale)
    }
}

/// The card's centered caption over the flag and amount.
private struct CardCenterStack: View {
    let caption: String
    let amount: String
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Text(caption)
                .font(.default(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.5))
            HStack(spacing: 8 * scale) {
                Image.regionFlag(.us)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30 * scale, height: 30 * scale)
                    .clipShape(Circle())
                Text(amount)
                    .font(.default(size: 38 * scale, weight: .bold))
                    .foregroundStyle(Color.textMain)
            }
        }
    }
}

/// A static illustration of a chat text bubble, matching `ChatBubbleView`'s
/// chrome (continuous radius 12, white-opacity fill by sender, hairline border,
/// 9/12 padding, message font). Decorative only — used in the Send empty state.
struct FakeChatBubble: View {

    let text: String
    let isFromSelf: Bool
    /// Caps the text width so a long bubble wraps; `nil` hugs the content.
    var maxTextWidth: CGFloat?

    var body: some View {
        Text(text)
            .font(.appTextMessage)
            .foregroundStyle(Color.textMain)
            .frame(maxWidth: maxTextWidth, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isFromSelf ? 0.08 : 0.02))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.03), lineWidth: 1)
            }
    }
}

// MARK: - Previews -

#Preview("Fake cash cards") {
    VStack(spacing: 24) {
        FakeCashCard(caption: "You received", amount: "$25.00", isFromSelf: false, width: 150)
        FakeCashCard(caption: "You sent", amount: "$60.00", isFromSelf: true, width: 210)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.backgroundMain)
}

#Preview("Fake chat bubbles") {
    VStack(alignment: .leading, spacing: 8) {
        FakeChatBubble(text: "Thanks for dinner!", isFromSelf: true)
        FakeChatBubble(
            text: "That's very kind of you. I had a great time last night",
            isFromSelf: false,
            maxTextWidth: 200
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.backgroundMain)
}
