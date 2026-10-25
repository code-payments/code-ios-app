//
//  PaymentRequestDeck.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// One request in the deck, already put into words.
struct PaymentRequestDeckItem: Identifiable, Hashable {
    let request: GroupPaymentRequest
    let card: PaymentRequestCardContent
    let amounts: String

    var id: PaymentRequestID { request.id }
}

/// The deck's open state, shared by the app-bar pill and the expanded overlay so the front card can
/// move between them.
@MainActor
@Observable
final class PaymentRequestDeckState {

    enum Phase {
        case collapsed
        /// The overlay is up with the front card still drawn at the pill's frame.
        case presenting
        case expanded
    }

    var order = PaymentRequestDeckOrder()
    private(set) var phase: Phase = .collapsed
    /// The pill's front card frame in global coordinates, where the shared front card starts and ends.
    var pillFrame: CGRect = .zero

    /// Lifts the front card into the overlay, then grows it into the expanded list.
    func expand() {
        guard phase == .collapsed else { return }
        phase = .presenting
        Task { @MainActor in
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) { phase = .expanded }
        }
    }

    /// Plays the expansion in reverse, back into the pill.
    func collapse() {
        guard phase == .expanded else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            phase = .presenting
        } completion: {
            self.phase = .collapsed
        }
    }
}

// MARK: - Pill -

/// The app-bar pill (concept B): the front request with up to two more peeking beneath it. Swipe
/// down cycles; tap expands.
struct PaymentRequestPill: View {

    let items: [PaymentRequestDeckItem]
    let accessibilityLabel: String
    @Bindable var state: PaymentRequestDeckState

    @State private var drag: CGFloat = 0
    @State private var frontSize = CGSize(width: 131, height: 43)

    private static let peekStep: CGFloat = 5
    private static let peekInset: CGFloat = 7

    var body: some View {
        ZStack(alignment: .top) {
            // The peeking cards, back first, each as tall as the front card and stepped in at both
            // edges so only their bottoms show.
            ForEach(Array(items.dropFirst().prefix(2).enumerated().reversed()), id: \.element.id) { offset, _ in
                let depth = CGFloat(offset + 1)
                PaymentRequestPillLayer(isBack: offset == 1)
                    .frame(width: max(frontSize.width - 2 * Self.peekInset * depth, 0), height: frontSize.height)
                    .offset(y: Self.peekStep * depth)
            }
            if let front = items.first {
                PaymentRequestPillFace(item: front)
                    .offset(y: drag)
                    .opacity(1 - min(0.45, drag / max(frontSize.height, 1) * 0.45))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        frontSize = $0.size
                        state.pillFrame = $0
                    }
            }
        }
        .padding(.bottom, Self.peekStep * CGFloat(min(max(items.count - 1, 0), 2)))
        .opacity(state.phase == .collapsed ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { state.expand() }
        .gesture(cycleGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { state.expand() }
        .accessibilityAction(named: "Next request") {
            guard items.count > 1 else { return }
            state.order.cycle()
        }
    }

    private var cycleGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let down = max(0, value.translation.height)
                // One request only pulls elastically.
                drag = items.count > 1 ? down : sqrt(down) * 2
            }
            .onEnded { value in
                let finishes = items.count > 1 && PaymentRequestDeckOrder.finishesCycle(
                    translation: value.translation.height,
                    predictedTranslation: value.predictedEndTranslation.height,
                    height: frontSize.height
                )
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    if finishes { state.order.cycle() }
                    drag = 0
                }
            }
    }
}

/// The parts of the front card that each move on their own between the pill and the expanded list.
private enum DeckPart: Hashable {
    case container
    case ring
    case title
    case amounts
}

private struct DeckPartID: Hashable {
    let request: PaymentRequestID
    let part: DeckPart
}

private extension View {
    /// Ties this view to the same part of the other state of the front card, when `namespace` is set.
    @ViewBuilder
    func deckPart(_ part: DeckPart, of request: PaymentRequestID, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            // Text keeps its own size and only moves, so it never truncates mid-flight.
            matchedGeometryEffect(
                id: DeckPartID(request: request, part: part),
                in: namespace,
                properties: part == .title || part == .amounts ? .position : .frame
            )
        } else {
            self
        }
    }
}

/// The front card of the pill: the ring, the title and "<paid> of <requested>".
struct PaymentRequestPillFace: View {

    let item: PaymentRequestDeckItem
    var namespace: Namespace.ID? = nil

    var body: some View {
        HStack(spacing: 8) {
            PaymentRequestRing(fraction: item.card.fraction, isEnded: item.card.isEnded)
                .deckPart(.ring, of: item.id, in: namespace)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.card.title)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                    .deckPart(.title, of: item.id, in: namespace)
                Text(item.amounts)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .deckPart(.amounts, of: item.id, in: namespace)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 90, alignment: .leading)
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .opacity(item.card.isEnded ? 0.4 : 1)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.rowSeparator))
                .opacity(item.card.isEnded ? 0.4 : 1)
                // The base keeps an ended card solid over the cards beneath it.
                .background(Color.backgroundMain, in: .rect(cornerRadius: 18))
                .deckPart(.container, of: item.id, in: namespace)
        }
    }
}

/// A card peeking beneath the pill's front card.
private struct PaymentRequestPillLayer: View {

    let isBack: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(isBack ? Color.textMain.opacity(0.08) : Color.backgroundSecondary)
            .background(Color.backgroundMain, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.rowSeparator))
    }
}

/// A request in the expanded deck: the timeline card's lines under the ring and title, on the app's
/// opaque card surface.
private struct PaymentRequestDeckCard: View {

    let item: PaymentRequestDeckItem
    var namespace: Namespace.ID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PaymentRequestRing(fraction: item.card.fraction, isEnded: item.card.isEnded, diameter: 36)
                    .deckPart(.ring, of: item.id, in: namespace)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Request")
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                    Text(item.card.title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(2)
                        .deckPart(.title, of: item.id, in: namespace)
                }
            }
            Text(item.card.progressLine)
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
                .deckPart(.amounts, of: item.id, in: namespace)
            PaymentRequestProgressBar(fraction: item.card.fraction, isEnded: item.card.isEnded)
            Text(item.card.statusLine)
                .font(.appTextCaption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .opacity(item.card.isEnded ? 0.4 : 1)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.rowSeparator))
                .deckPart(.container, of: item.id, in: namespace)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Expanded -

/// The expanded deck: every request as a full-width card beneath the app bar, over the dimmed chat.
/// The front card's container, ring, title and amounts move in from the pill and back on collapse.
struct PaymentRequestDeckOverlay: View {

    let items: [PaymentRequestDeckItem]
    @Bindable var state: PaymentRequestDeckState
    let open: (PaymentRequestID) -> Void

    @Namespace private var namespace
    @State private var origin: CGPoint = .zero
    @State private var cardHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private var isExpanded: Bool { state.phase == .expanded }

    var body: some View {
        ZStack(alignment: .top) {
            Color.backgroundMain
                .opacity(isExpanded ? 0.85 : 0)
                .ignoresSafeArea()
                .onTapGesture { state.collapse() }
                .accessibilityLabel("Collapse requests")
                .accessibilityAddTraits(.isButton)

            list
            if let front = items.first, !isExpanded {
                PaymentRequestPillFace(item: front, namespace: namespace)
                    .frame(width: state.pillFrame.width, height: state.pillFrame.height)
                    .position(x: state.pillFrame.midX - origin.x, y: state.pillFrame.midY - origin.y)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
            // Dragging up, or swiping in from the leading edge as swipe-back would, collapses.
            let fromEdge = value.startLocation.x < 24 && value.translation.width > 60
            if value.translation.height < -40 || fromEdge { state.collapse() }
        })
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index == 0 {
                        // While the front card is still the pill, an invisible copy holds its slot so
                        // the rest know where to start from.
                        if isExpanded {
                            card(item, namespace: namespace)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                        } else {
                            card(item)
                                .hidden()
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                        }
                    } else {
                        // The rest slide out from beneath the front card and back under it on collapse.
                        card(item)
                            .offset(y: isExpanded ? 0 : -CGFloat(index) * (cardHeight + 10))
                            .opacity(isExpanded ? 1 : 0)
                            .zIndex(Double(-index))
                    }
                }

                Capsule()
                    .fill(Color.textSecondary)
                    .opacity(isExpanded ? 1 : 0)
                    .frame(width: 36, height: 5)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            // The scroll view covers the dimmed chat, so the space below the cards takes the
            // scrim's tap; the cards' own buttons win over it.
            .frame(minHeight: viewportHeight, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { state.collapse() }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .allowsHitTesting(isExpanded)
    }

    private func card(_ item: PaymentRequestDeckItem, namespace: Namespace.ID? = nil) -> some View {
        Button { open(item.id) } label: {
            PaymentRequestDeckCard(item: item, namespace: namespace)
        }
        .buttonStyle(.plain)
    }
}

extension PaymentRequests {
    /// `conversationID`'s deck, worded for the viewer, rotated by `order`. Requests whose title
    /// isn't open yet stay out until it is.
    func deckItems(
        for conversationID: ConversationID,
        order: PaymentRequestDeckOrder,
        copy: PaymentRequestCopy,
        now: Date
    ) -> [PaymentRequestDeckItem] {
        order.apply(to: deck(for: conversationID, at: now)).compactMap { request in
            guard let text = text(of: request) else { return nil }
            return PaymentRequestDeckItem(
                request: request,
                card: PaymentRequestCardContent(request: request, title: text.title, copy: copy, now: now),
                amounts: copy.deckAmounts(request)
            )
        }
    }
}
