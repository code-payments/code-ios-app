//
//  ComposerCardSuggestionStrip.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The offer above the composer to send a mentioned person's card, and the card itself once taken.
///
/// Offered, it is a glass row in the reply quote's material: the person's avatar, what tapping does,
/// and who it is. Taken, the row gives way to the card exactly as the transcript will draw it, so the
/// sender sees what they are sending. Either way the ✕ takes it back without touching the draft.
///
/// The strip is the card's height in both phases on purpose. The bar only travels when a strip opens
/// or closes; a strip that changes height while open is taken flat (see
/// `ChatScreenViewController.setBarHeight`), so an offer shorter than the card would make the bar
/// jump when it is taken. At one height the swap happens inside the strip, where it can spring.
struct ComposerCardSuggestionStrip: View {

    let suggestion: CardSuggestionModel.Suggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    /// This strip's own values.
    enum Layout {
        /// The reply quote's margin, so the two strips stack on one margin.
        static let inset: CGFloat = 12
        /// Between the row's content and the ✕.
        static let gutter: CGFloat = 9
        /// After the offer's ✕. Tighter than the card's trailing padding because the ✕'s hit area is
        /// wider than its disc and already leaves room.
        static let dismissInset: CGFloat = 8
        /// Where the card starts as it springs in, grown from its leading edge.
        static let cardEnterScale: CGFloat = 0.9
        /// Where the offer's avatar starts as the strip opens.
        static let avatarEnterScale: CGFloat = 0.6
    }

    /// The offer's copy, Title Case where it is a label.
    enum Copy {
        static func offer(handle: String) -> String { "Share \(handle)'s card" }
        static let offerOwn = "Share your card"
        static let attachedLabel = "Card attached"
        static let dismissOffer = "Dismiss card suggestion"
        static let removeCard = "Remove card"
    }

    /// The spring the swap between offer and card rides. Only the scale and opacity of what is
    /// inside the strip move on it — the bar's own edge stays on the no-overshoot reply spring, since
    /// the transcript tracks that edge every frame.
    private static let swapSpring = ChatMotion.swap.animation

    @State private var avatarShown = false

    var body: some View {
        ZStack(alignment: .leading) {
            // Sizes the strip to the card in both phases. The offer's avatar row alone is shorter
            // than the card's three lines, and the bar takes a height change flat while open.
            LinkUserCardContent(state: .resolved(person), linkedHandle: nil, fillsWidth: false)
                .hidden()
                .accessibilityHidden(true)
            switch suggestion.phase {
            case .suggested:
                offer
                    .frame(maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .leading)))
            case .attached:
                attached
                    .transition(
                        .opacity.combined(with: .scale(scale: Layout.cardEnterScale, anchor: .leading))
                    )
            }
        }
        .animation(Self.swapSpring, value: suggestion.phase)
        .padding(.horizontal, Layout.inset)
        .padding(.top, Layout.inset)
        .padding(.bottom, Layout.inset - BarMetrics.contentPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer-card-suggestion")
    }

    // MARK: - Offer -

    private var offer: some View {
        HStack(spacing: Layout.gutter) {
            Button(action: onAccept) {
                HStack(spacing: LinkUserCardContent.Layout.avatarGap) {
                    avatar
                    VStack(alignment: .leading, spacing: LinkUserCardContent.Layout.lineGap) {
                        Text(offerTitle)
                            .font(.appTextMessage)
                            .foregroundStyle(Color.textMain)
                        Text(person.displayName)
                            .font(.appTextCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(offerTitle), \(person.displayName)")
            .accessibilityIdentifier("card-suggestion-accept")

            ComposerStripDismissButton(action: onDismiss)
                .accessibilityLabel(Copy.dismissOffer)
                .accessibilityIdentifier("card-suggestion-dismiss")
        }
        .padding(.vertical, LinkUserCardContent.Layout.verticalPadding)
        .padding(.leading, LinkUserCardContent.Layout.leadingPadding)
        .padding(.trailing, Layout.dismissInset)
        .modifier(QuoteGround())
    }

    /// The avatar at the card's size, so it lands where the card's avatar will. Springs in as the strip
    /// opens: the reveal itself does not overshoot, so the spring lives on the one thing that can.
    private var avatar: some View {
        ContactAvatarView(
            id: person.avatarID,
            displayName: person.displayName,
            imageData: person.imageData,
            blurhash: person.blurHash,
            size: LinkUserCardContent.Layout.avatar
        )
        .scaleEffect(avatarShown ? 1 : Layout.avatarEnterScale)
        .opacity(avatarShown ? 1 : 0)
        .onAppear {
            withAnimation(ChatMotion.reaction.animation) { avatarShown = true }
        }
    }

    private var offerTitle: String {
        person.isOwn ? Copy.offerOwn : Copy.offer(handle: "@\(suggestion.username.value)")
    }

    // MARK: - Attached -

    /// The card as it will be sent. Not tappable here: it would open the person, and the sender is
    /// in the middle of writing.
    private var attached: some View {
        HStack(spacing: Layout.gutter) {
            LinkUserCardContent(state: .resolved(person), linkedHandle: nil, fillsWidth: false)
                .allowsHitTesting(false)
                .accessibilityLabel("\(Copy.attachedLabel): \(person.displayName)")
            Spacer(minLength: 0)
            ComposerStripDismissButton(action: onDismiss)
                .accessibilityLabel(Copy.removeCard)
                .accessibilityIdentifier("card-suggestion-remove")
        }
    }

    private var person: LinkCard.User.Resolved { suggestion.person }
}
