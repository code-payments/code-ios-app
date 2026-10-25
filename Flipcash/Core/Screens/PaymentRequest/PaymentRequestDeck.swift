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
        /// The overlay is up and the front card is moving, or resting at the pill on its way out.
        case presenting
        case expanded
    }

    var order = PaymentRequestDeckOrder()
    /// How far the front card is from the pill (0) to the expanded list (1). Only ever changed under
    /// one spring, so a new target retargets it from wherever it is.
    private(set) var progress: CGFloat = 0
    /// The target: the deck is open or on its way there.
    private(set) var isOpen = false
    private(set) var isOverlayPresented = false
    /// Open and at rest, so the list's own front card shows in place of the moving one.
    private(set) var isSettled = false
    /// The front card's parts in global coordinates, in the pill and in the expanded list.
    var pillFrames: [DeckPart: CGRect] = [:]
    var cardFrames: [DeckPart: CGRect] = [:]
    /// The pill's Dynamic Type size. The toolbar can lay its text out at a different size than the
    /// overlay, so the moving copy draws the pill's text at this one to land on it exactly.
    var pillTypeSize: DynamicTypeSize = .large
    private var generation = 0

    private static let motion = Animation.spring(duration: 0.4, bounce: 0.12)

    var phase: Phase {
        guard isOverlayPresented else { return .collapsed }
        return isOpen ? .expanded : .presenting
    }

    /// Grows the front card from the pill into the expanded list, from wherever it is.
    func expand() {
        guard !isOpen else { return }
        isOpen = true
        generation += 1
        let generation = generation
        if isOverlayPresented {
            move(to: 1, generation: generation)
        } else {
            isOverlayPresented = true
            // One layout pass first, so the list's front card is measured before it moves.
            Task { @MainActor in self.move(to: 1, generation: generation) }
        }
    }

    /// Shrinks the front card back into the pill, from wherever it is.
    func collapse() {
        guard isOpen else { return }
        isOpen = false
        isSettled = false
        generation += 1
        move(to: 0, generation: generation)
    }

    private func move(to target: CGFloat, generation: Int) {
        guard generation == self.generation else { return }
        // `.removed` waits for the spring to come fully to rest, so nothing swaps while it still moves.
        withAnimation(Self.motion, completionCriteria: .removed) {
            progress = target
        } completion: {
            guard generation == self.generation else { return }
            if target == 1 {
                self.isSettled = true
            } else {
                self.isOverlayPresented = false
            }
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

    @Environment(\.dynamicTypeSize) private var typeSize
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
                PaymentRequestPillFace(item: front) { state.pillFrames[$0] = $1 }
                    .offset(y: drag)
                    .opacity(1 - min(0.45, drag / max(frontSize.height, 1) * 0.45))
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { frontSize = $0 }
                    // The moving copy stands in for it until it lands back here.
                    .opacity(state.phase == .collapsed ? 1 : 0)
            }
        }
        .padding(.bottom, Self.peekStep * CGFloat(min(max(items.count - 1, 0), 2)))
        .onChange(of: typeSize, initial: true) { state.pillTypeSize = typeSize }
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

/// The parts of the front card measured in both states, so the moving card can lay each one out
/// between where it sits in the pill and where it sits in the expanded list.
enum DeckPart: Hashable {
    case container
    case ring
    case title
    case amounts
    /// The parts only the expanded card shows.
    case label
    case bar
    case status
}

/// Reports a part's global frame.
typealias DeckPartMeasure = (DeckPart, CGRect) -> Void

private extension View {
    /// Reports this view's global frame as `part`, when `measure` is set.
    @ViewBuilder
    func deckPart(_ part: DeckPart, _ measure: DeckPartMeasure?) -> some View {
        if let measure {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { measure(part, $0) }
        } else {
            self
        }
    }
}

/// The front card of the pill: the ring, the title and "<paid> of <requested>".
struct PaymentRequestPillFace: View {

    let item: PaymentRequestDeckItem
    var measure: DeckPartMeasure? = nil

    var body: some View {
        HStack(spacing: 8) {
            PaymentRequestRing(fraction: item.card.fraction, isEnded: item.card.isEnded, isClosed: item.request.status == .closed)
                .deckPart(.ring, measure)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.card.title)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                    .deckPart(.title, measure)
                Text(item.amounts)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .deckPart(.amounts, measure)
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
                .deckPart(.container, measure)
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
    var measure: DeckPartMeasure? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PaymentRequestRing(fraction: item.card.fraction, isEnded: item.card.isEnded, isClosed: item.request.status == .closed, diameter: 36)
                    .deckPart(.ring, measure)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Request")
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                        .deckPart(.label, measure)
                    Text(item.card.title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(2)
                        .deckPart(.title, measure)
                }
            }
            Text(item.card.progressLine)
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
                .deckPart(.amounts, measure)
            PaymentRequestProgressBar(fraction: item.card.fraction, isEnded: item.card.isEnded)
                .deckPart(.bar, measure)
            Text(item.card.statusLine)
                .font(.appTextCaption)
                .foregroundStyle(Color.textSecondary)
                .deckPart(.status, measure)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .opacity(item.card.isEnded ? 0.4 : 1)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.rowSeparator))
                .deckPart(.container, measure)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Expanded -

/// The expanded deck: every request as a full-width card beneath the app bar, over the dimmed chat.
/// While it opens or closes, `PaymentRequestDeckMorph` draws the front card between the pill and the
/// list.
struct PaymentRequestDeckOverlay: View {

    let items: [PaymentRequestDeckItem]
    @Bindable var state: PaymentRequestDeckState
    let open: (PaymentRequestID) -> Void

    @State private var origin: CGPoint = .zero
    @State private var cardHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.backgroundMain
                .opacity(0.85 * state.progress)
                .ignoresSafeArea()
                .onTapGesture { state.collapse() }
                .accessibilityLabel("Collapse requests")
                .accessibilityAddTraits(.isButton)

            list
            if let front = items.first, !state.isSettled {
                PaymentRequestDeckMorph(
                    item: front,
                    progress: state.progress,
                    pill: state.pillFrames,
                    card: state.cardFrames,
                    pillTypeSize: state.pillTypeSize,
                    origin: origin
                )
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
                        // Always laid out and measured; it shows only at rest, when the moving copy
                        // drawn from its measurements would sit exactly on it.
                        card(item) { state.cardFrames[$0] = $1 }
                            .opacity(state.isSettled ? 1 : 0)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                    } else {
                        // The rest slide out from beneath the front card and back under it on collapse.
                        card(item)
                            .offset(y: -CGFloat(index) * (cardHeight + 10) * (1 - state.progress))
                            .opacity(state.progress)
                            .zIndex(Double(-index))
                    }
                }

                Capsule()
                    .fill(Color.textSecondary)
                    .opacity(state.isOpen ? 1 : 0)
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
        .allowsHitTesting(state.isOpen)
    }

    private func card(_ item: PaymentRequestDeckItem, measure: DeckPartMeasure? = nil) -> some View {
        Button { open(item.id) } label: {
            PaymentRequestDeckCard(item: item, measure: measure)
        }
        .buttonStyle(.plain)
    }
}

/// The front card part way between the pill (`progress` 0) and the expanded list (1), laid out from
/// both states' measured frames so it lands exactly on either. Text the two share moves and scales
/// across; the expanded card's own lines ride inside the container and fade in over the last 40%.
private struct PaymentRequestDeckMorph: View, Animatable {

    let item: PaymentRequestDeckItem
    var progress: CGFloat
    let pill: [DeckPart: CGRect]
    let card: [DeckPart: CGRect]
    let pillTypeSize: DynamicTypeSize
    let origin: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let pillRing: CGFloat = 26
    private static let cardRing: CGFloat = 36
    /// appTextMedium over appTextCaption, the title's two sizes.
    private static let titleScale: CGFloat = 16 / 12
    /// appTextSmall over appTextCaption, the amounts' two sizes.
    private static let amountsScale: CGFloat = 14 / 12

    var body: some View {
        let p = min(max(progress, 0), 1)
        if let pillBox = pill[.container], let cardBox = card[.container] {
            let box = lerp(pillBox, cardBox, p)
            let content = item.card.isEnded ? 0.4 : 1.0
            // The title reads the same in both, so its two sizes cross over the whole move. The
            // amounts read differently, so one leaves before the other arrives rather than overlap.
            let outgoing = 1 - p * p
            let incoming = 1 - (1 - p) * (1 - p)
            let amountsOut = max(0, 1 - p / 0.35)
            let amountsIn = min(1, max(0, (p - 0.35) / 0.3))
            let extras = max(0, (p - 0.6) / 0.4)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18 + (12 - 18) * p)
                    .fill(Color.backgroundSecondary)
                    .opacity(item.card.isEnded ? 0.4 + 0.6 * p : 1)
                    .background(Color.backgroundMain, in: .rect(cornerRadius: 18 + (12 - 18) * p))
                    .overlay(RoundedRectangle(cornerRadius: 18 + (12 - 18) * p).strokeBorder(Color.rowSeparator))
                    .place(box, origin)

                Group {
                    ring(p)
                    shared(.title, scale: Self.titleScale, p: p, outgoing: outgoing, incoming: incoming) { isCard in
                        Text(item.card.title)
                            .font(isCard ? .appTextMedium : .appTextCaption)
                            .foregroundStyle(Color.textMain)
                            .lineLimit(isCard ? 2 : 1)
                    }
                    shared(.amounts, scale: Self.amountsScale, p: p, outgoing: amountsOut, incoming: amountsIn) { isCard in
                        Text(isCard ? item.card.progressLine : item.amounts)
                            .font(isCard ? .appTextSmall : .appTextCaption)
                            .foregroundStyle(isCard ? Color.textMain : Color.textSecondary)
                            .lineLimit(1)
                    }
                    Group {
                        extra(.label, in: box, from: cardBox) {
                            Text("Request").font(.appTextCaption).foregroundStyle(Color.textSecondary)
                        }
                        extra(.bar, in: box, from: cardBox, stretches: true) {
                            PaymentRequestProgressBar(fraction: item.card.fraction, isEnded: item.card.isEnded)
                        }
                        extra(.status, in: box, from: cardBox) {
                            Text(item.card.statusLine).font(.appTextCaption).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .opacity(extras)
                }
                .opacity(content)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The ring at its size part way between the two, drawn from whichever end is nearer so its "$"
    /// keeps the right weight.
    @ViewBuilder
    private func ring(_ p: CGFloat) -> some View {
        if let from = pill[.ring], let to = card[.ring] {
            let frame = lerp(from, to, p)
            let base = p < 0.5 ? Self.pillRing : Self.cardRing
            PaymentRequestRing(
                fraction: item.card.fraction,
                isEnded: item.card.isEnded,
                isClosed: item.request.status == .closed,
                diameter: base
            )
            .scaleEffect(frame.width / base)
            .frame(width: base, height: base)
            .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
        }
    }

    /// A part both states show: the pill's version scales up and fades out while the card's scales
    /// down to meet it and fades in, both anchored at the moving top-leading corner.
    @ViewBuilder
    private func shared(
        _ part: DeckPart,
        scale: CGFloat,
        p: CGFloat,
        outgoing: CGFloat,
        incoming: CGFloat,
        @ViewBuilder text: @escaping (Bool) -> some View
    ) -> some View {
        if let from = pill[part], let to = card[part] {
            let corner = CGPoint(x: from.minX + (to.minX - from.minX) * p - origin.x, y: from.minY + (to.minY - from.minY) * p - origin.y)
            let grow = 1 + (scale - 1) * p
            text(false)
                .dynamicTypeSize(pillTypeSize)
                .frame(width: from.width, height: from.height, alignment: .topLeading)
                .scaleEffect(grow, anchor: .topLeading)
                .offset(x: corner.x, y: corner.y)
                .opacity(outgoing)
            text(true)
                .frame(width: to.width, height: to.height, alignment: .topLeading)
                .scaleEffect(grow / scale, anchor: .topLeading)
                .offset(x: corner.x, y: corner.y)
                .opacity(incoming)
        }
    }

    /// A part only the expanded card shows, kept at the same relative spot inside the moving container.
    @ViewBuilder
    private func extra(
        _ part: DeckPart,
        in box: CGRect,
        from cardBox: CGRect,
        stretches: Bool = false,
        @ViewBuilder content: () -> some View
    ) -> some View {
        if let rest = card[part], cardBox.width > 0, cardBox.height > 0 {
            let x = box.minX + (rest.minX - cardBox.minX) * box.width / cardBox.width
            let y = box.minY + (rest.minY - cardBox.minY) * box.height / cardBox.height
            content()
                .frame(width: stretches ? rest.width * box.width / cardBox.width : rest.width, height: rest.height, alignment: .topLeading)
                .offset(x: x - origin.x, y: y - origin.y)
        }
    }

    private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: a.minX + (b.minX - a.minX) * t,
            y: a.minY + (b.minY - a.minY) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }
}

private extension View {
    /// Lays this view out at `frame`, a global frame, inside a top-leading container at `origin`.
    func place(_ frame: CGRect, _ origin: CGPoint) -> some View {
        self.frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX - origin.x, y: frame.minY - origin.y)
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
