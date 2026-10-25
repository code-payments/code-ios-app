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
    /// The pill's frame in global coordinates, where the shared front card starts and ends.
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

/// The app-bar pill: the front request with up to two more peeking beneath it. Swipe down cycles;
/// tap expands.
struct PaymentRequestPill: View {

    let items: [PaymentRequestDeckItem]
    let accessibilityLabel: String
    @Bindable var state: PaymentRequestDeckState

    @State private var drag: CGFloat = 0
    @State private var height: CGFloat = 43

    private static let peekOffset: CGFloat = 5

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                if index == 0 {
                    PaymentRequestPillFace(item: item)
                        .offset(y: drag)
                        .opacity(1 - min(0.45, drag / max(height, 1) * 0.45))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                } else {
                    PaymentRequestPillLayer(index: index)
                        .offset(x: CGFloat(index) * 7, y: CGFloat(index) * Self.peekOffset)
                }
            }
        }
        .opacity(state.phase == .collapsed ? 1 : 0)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.pillFrame = $0 }
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
                    height: height
                )
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    if finishes { state.order.cycle() }
                    drag = 0
                }
            }
    }
}

/// The front card of the pill: the ring, the title and "<paid> of <requested>".
struct PaymentRequestPillFace: View {

    let item: PaymentRequestDeckItem

    var body: some View {
        HStack(spacing: 8) {
            PaymentRequestRing(fraction: item.card.fraction, isEnded: item.card.isEnded)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.card.title)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                Text(item.amounts)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 90, alignment: .leading)
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(Color.backgroundMain, in: .rect(cornerRadius: 18))
        .background(Color.textMain.opacity(0.06), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.textMain.opacity(0.1)))
        .opacity(item.card.isEnded ? 0.4 : 1)
    }
}

/// A card peeking beneath the pill's front card.
private struct PaymentRequestPillLayer: View {

    let index: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.textMain.opacity(index == 1 ? 0.06 : 0.08))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.textMain.opacity(0.1)))
            .frame(height: 36)
            .padding(.trailing, CGFloat(index) * 14)
    }
}

// MARK: - Expanded -

/// The expanded deck: every request as a full-width card beneath the app bar, over the dimmed chat.
/// The front card moves in from the pill and back on collapse.
struct PaymentRequestDeckOverlay: View {

    let items: [PaymentRequestDeckItem]
    @Bindable var state: PaymentRequestDeckState
    let open: (PaymentRequestID) -> Void

    @Namespace private var namespace
    @State private var origin: CGPoint = .zero

    private var isExpanded: Bool { state.phase == .expanded }

    var body: some View {
        ZStack(alignment: .top) {
            Color.backgroundMain
                .opacity(isExpanded ? 0.85 : 0)
                .ignoresSafeArea()
                .onTapGesture { state.collapse() }
                .accessibilityLabel("Collapse requests")
                .accessibilityAddTraits(.isButton)

            if let front = items.first {
                if isExpanded {
                    list
                } else {
                    PaymentRequestPillFace(item: front)
                        .matchedGeometryEffect(id: front.id, in: namespace)
                        .frame(width: state.pillFrame.width, height: state.pillFrame.height)
                        .position(x: state.pillFrame.midX - origin.x, y: state.pillFrame.midY - origin.y)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                }
            }
        }
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
            if value.translation.height < -40 { state.collapse() }
        })
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(items) { item in
                    Button { open(item.id) } label: {
                        PaymentRequestCard(content: item.card)
                            .padding(14)
                            .background(Color.textMain.opacity(0.1), in: .rect(cornerRadius: 12))
                            .opacity(item.card.isEnded ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .matchedGeometryEffect(id: item.id, in: namespace, isSource: item.id == items.first?.id)
                    .transition(.offset(y: -24).combined(with: .opacity))
                }

                Capsule()
                    .fill(Color.textSecondary)
                    .frame(width: 36, height: 5)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
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
