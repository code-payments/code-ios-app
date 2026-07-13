//
//  SendConversationHero.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A cash card and two chat bubbles framed inside a faint "chat preview" panel
/// whose bottom fades into the background via a `mask`. Sells the Send feature
/// on the sheet's phone-gating empty state (`ConnectPhoneEmptyState`).
///
/// The cards and bubbles carry their real sender/recipient fills, so the muted
/// look comes from those subtle fills plus the fade — not a global opacity.
/// Hidden from VoiceOver so the placeholder amounts aren't read as real money.
struct SendConversationHero: View {
    var body: some View {
        // Laid out like a real conversation: the self messages (the sent card
        // and "Thanks for dinner!") hug the trailing edge, the other person's
        // reply hugs the leading edge.
        VStack(spacing: 6) {
            FakeCashCard(caption: "You sent", amount: "$60.00", isFromSelf: true, width: 180)
                .frame(maxWidth: .infinity, alignment: .trailing)
            FakeChatBubble(text: "Thanks for dinner!", isFromSelf: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
            FakeChatBubble(
                text: "That's very kind of you. I had a great time last night",
                isFromSelf: false,
                maxTextWidth: 200
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.035))
        }
        .frame(maxWidth: 300)
        .mask {
            // Solid at the top edge of the panel, fading out toward the bottom
            // so it melts into the background above the headline.
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.72),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview -

#Preview {
    SendConversationHero()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundMain)
}
