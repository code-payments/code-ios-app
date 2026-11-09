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
    /// "$180 of $520".
    let amounts: String
    let viewerStatus: PaymentRequestViewerStatus
    /// The viewer's unpaid share while the request is open: "$20". Nil when they owe nothing on it.
    let owedShare: String?
    /// The status line without "to pay": "2 days left".
    let timeLeft: String

    var id: PaymentRequestID { request.id }
}

/// The deck's open state, shared by the stack under the app bar and the expanded overlay so the front
/// card can move between them.
@MainActor
@Observable
final class PaymentRequestDeckState {

    enum Phase {
        case collapsed
        /// The overlay is up and the front card is moving, or resting at the stack on its way out.
        case presenting
        case expanded
    }

    var order = PaymentRequestDeckOrder()
    /// How far the front card is from the stack (0) to the expanded list (1). Only ever changed under
    /// one spring, so a new target retargets it from wherever it is.
    private(set) var progress: CGFloat = 0
    /// The target: the deck is open or on its way there.
    private(set) var isOpen = false
    private(set) var isOverlayPresented = false
    /// Open and at rest, so the list's own front card shows in place of the moving one.
    private(set) var isSettled = false
    /// The front card's parts in global coordinates in the stack, and in the expanded list.
    var stackFrames: [DeckPart: CGRect] = [:]
    var cardFrames: [DeckPart: CGRect] = [:]
    /// The app bar's trailing slot in global coordinates, where the expanded deck's close button sits.
    var closeSlot: CGRect?
    /// The stack's Dynamic Type size, so the moving copy draws the stack's text at the stack's own
    /// size and lands on it exactly.
    var stackTypeSize: DynamicTypeSize = .large
    private var generation = 0

    private static let motion = Animation.spring(duration: 0.4, bounce: 0.12)

    var phase: Phase {
        guard isOverlayPresented else { return .collapsed }
        return isOpen ? .expanded : .presenting
    }

    /// Grows the front card from the stack into the expanded list, from wherever it is.
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

    /// Shrinks the front card back into the stack, from wherever it is.
    func collapse() {
        guard isOpen else { return }
        isOpen = false
        isSettled = false
        generation += 1
        move(to: 0, generation: generation)
    }

    /// Puts the front card back at the stack with no animation, for when the deck is hidden behind a
    /// screen. The overlay stays up, drawing the card where the stack is, until `endPresentation()`.
    func snapToStack() {
        guard isOpen else { return }
        isOpen = false
        isSettled = false
        generation += 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { progress = 0 }
    }

    /// Takes the overlay down once the card rests at the stack, handing back to the stack itself.
    func endPresentation() {
        guard !isOpen, progress == 0 else { return }
        isOverlayPresented = false
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

// MARK: - Presence -

/// Whether the stack is under the app bar, how far it has faded in, and which cards it draws while a
/// request leaves. It fades in and out in place when requests arrive or run out after the chat is on
/// screen, and is simply there when the chat opens with requests already known.
///
/// A request that ends leaves the deck. One that completed stays where it was, with its ring swept to
/// full, for ``sweep``; then the remaining cards close the gap with the deck's settle motion.
@MainActor
@Observable
final class PaymentRequestDeckPresence {

    /// The stack is mounted; it outlives `isVisible` by the fade-out.
    private(set) var isMounted = false
    /// Drives the stack's opacity and scale.
    private(set) var isVisible = false
    /// The last non-empty deck, drawn while the stack fades out after the requests are gone.
    private(set) var lastItems: [PaymentRequestDeckItem] = []
    /// The cards drawn in place of the live deck while departing requests finish leaving.
    private(set) var held: [PaymentRequestDeckItem]?

    /// The stack fades in when it first shows rather than being there from its first frame.
    private(set) var fadesIn = false
    private var hasSettled = false
    /// The live deck as of the last update.
    @ObservationIgnored private var live: [PaymentRequestDeckItem] = []
    @ObservationIgnored private var release: Task<Void, Never>?

    static let fade = Animation.easeOut(duration: 0.25)
    /// How the remaining cards close the gap a departed request leaves.
    static let settle = Animation.spring(duration: 0.35, bounce: 0.15)
    /// How long a completed request stays while its ring sweeps to full.
    static let sweep: Duration = .milliseconds(300)

    /// The items the stack draws: the held deck, the live one, or the last one while it fades out.
    func items(_ live: [PaymentRequestDeckItem]) -> [PaymentRequestDeckItem] {
        if let held { return held }
        return live.isEmpty ? lastItems : live
    }

    /// The items the expanded list draws: the held deck, or the live one.
    func listItems(_ live: [PaymentRequestDeckItem]) -> [PaymentRequestDeckItem] {
        held ?? live
    }

    /// Follows the deck's contents; the first call sets the state without a fade. `completed` returns
    /// a departed request's card as it reads now when the request completed, nil when it left any
    /// other way. With `animates` false, as under Reduce Motion, departures apply at once.
    func update(
        _ items: [PaymentRequestDeckItem],
        completed: (PaymentRequestID) -> PaymentRequestDeckItem?,
        animates: Bool
    ) {
        let previous = held ?? live
        live = items
        guard hasSettled else {
            hasSettled = true
            if !items.isEmpty { lastItems = items }
            isMounted = !items.isEmpty
            isVisible = !items.isEmpty
            return
        }
        release?.cancel()
        let departing = animates ? Self.holding(previous: previous, live: items, completed: completed) : nil
        guard let departing else {
            held = nil
            follow(items)
            return
        }
        held = departing.items
        lastItems = departing.items
        let delay = departing.sweeps ? Self.sweep : .zero
        release = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            withAnimation(Self.settle) { self.held = nil }
            self.follow(self.live)
        }
    }

    /// What the stack holds while requests leave: `previous` in its order, each still-live card as it
    /// reads now, a completed one as `completed` returns it, and any other departed card as it was,
    /// followed by cards that just arrived. Nil when nothing left. `sweeps` is whether any of them
    /// completed and needs time for its ring.
    static func holding(
        previous: [PaymentRequestDeckItem],
        live: [PaymentRequestDeckItem],
        completed: (PaymentRequestID) -> PaymentRequestDeckItem?
    ) -> (items: [PaymentRequestDeckItem], sweeps: Bool)? {
        let liveByID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let departed = previous.filter { liveByID[$0.id] == nil }
        guard !departed.isEmpty else { return nil }
        var sweeps = false
        var items = previous.map { item in
            if let current = liveByID[item.id] { return current }
            if let done = completed(item.id) {
                sweeps = true
                return done
            }
            return item
        }
        let kept = Set(previous.map(\.id))
        items += live.filter { !kept.contains($0.id) }
        return (items, sweeps)
    }

    /// Shows or hides the stack for the live deck `items`.
    private func follow(_ items: [PaymentRequestDeckItem]) {
        if !items.isEmpty { lastItems = items }
        let hasItems = !items.isEmpty
        guard hasItems != isVisible else { return }
        if hasItems {
            // The stack runs its own fade once it appears; this animation moves what sits below it.
            fadesIn = true
            withAnimation(Self.fade) {
                isMounted = true
                isVisible = true
            }
        } else {
            withAnimation(Self.fade) {
                isVisible = false
            } completion: { [weak self] in
                guard let self, !self.isVisible else { return }
                withAnimation(Self.fade) { self.isMounted = false }
                self.lastItems = []
            }
        }
    }
}

/// Fades and scales the stack in place as `presence` shows and hides it.
struct PaymentRequestDeckAppearance: ViewModifier {

    let presence: PaymentRequestDeckPresence
    @State private var hasAppeared = false

    private var isShown: Bool {
        presence.isVisible && (hasAppeared || !presence.fadesIn)
    }

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .scaleEffect(isShown ? 1 : 0.95)
            .allowsHitTesting(isShown)
            .onAppear {
                withAnimation(PaymentRequestDeckPresence.fade) { hasAppeared = true }
            }
    }
}

// MARK: - Stack -

/// The collapsed deck (concept node 12670:1262): the front request with up to two more peeking
/// beneath it, as a full-width stack of cards under the app bar. Swipe down cycles; tap expands.
struct PaymentRequestStack: View {

    let items: [PaymentRequestDeckItem]
    let accessibilityLabel: String
    @Bindable var state: PaymentRequestDeckState
    /// Starts paying the viewer's share of a request, from the front card's Pay button.
    var pay: ((PaymentRequestID) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The finger's vertical travel, not the front card's: the card rubber-bands past one card height
    /// going down, and only pulls a few points going up.
    @State private var drag: CGFloat = 0
    @State private var frontHeight: CGFloat = 43

    private static let peekStep: CGFloat = 5
    /// How much each step back shrinks a card, so its sides tuck in under the one in front.
    private static let depthScale: CGFloat = 0.08
    private static let depthDim: CGFloat = 0.25
    private static let settle = PaymentRequestDeckPresence.settle
    /// How long a card's own change (a paid badge arriving) takes to fade in, which a re-sort waits out.
    private static let fadeDuration = 0.3
    /// The furthest an upward drag pulls the front card.
    static let maxUpwardPull: CGFloat = 12

    var body: some View {
        // The front request at rest sets the stack's size and is what the deck measures; the cards
        // drawn over it move freely without feeding back into the layout.
        ZStack(alignment: .top) {
            if let front = items.first {
                PaymentRequestStackFace(item: front, measure: report)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { frontHeight = $0 }
                    .opacity(0)
            }
        }
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    card(item, at: index)
                }
            }
        }
        .padding(.bottom, Self.peekStep * CGFloat(min(max(items.count - 1, 0), 2)))
        .onChange(of: typeSize, initial: true) { state.stackTypeSize = typeSize }
        .contentShape(Rectangle())
        .onTapGesture { state.expand() }
        .gesture(cycleGesture)
        .accessibilityRepresentation {
            Button(accessibilityLabel) { state.expand() }
                .accessibilityAction(named: "Next request") {
                    guard items.count > 1 else { return }
                    withAnimation(Self.settle) { state.order.cycle() }
                }
            if let front = items.first, let share = front.owedShare, let pay {
                Button("Pay \(share)") { pay(front.id) }
            }
        }
    }

    /// Records a part of the front card for the expand morph.
    private func report(_ part: DeckPart, _ frame: CGRect) {
        state.stackFrames[part] = frame
    }

    /// `item` at `index` in the deck: the front card follows the finger, and each card behind rises
    /// a step toward the front as the drag nears one card height. Past the second card they stack
    /// in the back slot, so a card sent to the back slides up under the others.
    private func card(_ item: PaymentRequestDeckItem, at index: Int) -> some View {
        let height = max(frontHeight, 1)
        let rise = items.count > 1 ? min(1, max(0, drag) / height) : 0
        let depth = index == 0 ? 0 : min(max(0, CGFloat(index) - rise), 2)
        let scale = index == 0 ? 1 - Self.depthScale * 0.5 * rise : 1 - Self.depthScale * depth
        // Anchored at the top, a card's scaled bottom sits a peek step lower per step back.
        let offset = index == 0 ? frontTravel(height: height) : height * (1 - scale) + Self.peekStep * depth
        return PaymentRequestStackFace(item: item, fillsWidth: true, pay: pay)
            .overlay {
                RoundedRectangle(cornerRadius: PaymentRequestStackFace.cornerRadius)
                    .fill(Color.backgroundMain.opacity(Self.depthDim * depth))
                    .allowsHitTesting(false)
            }
            .scaleEffect(scale, anchor: .top)
            .offset(y: offset)
            // The moving copy stands in for the front card until it lands back here.
            .opacity(index == 0 && state.phase != .collapsed ? 0 : 1)
            // Only the front card's Pay button takes a tap; the rest peek.
            .allowsHitTesting(index == 0)
            .zIndex(Double(items.count - index))
            // A move that no gesture drives, such as a paid request sorting behind an owed one,
            // settles after the card's own change has faded. Cycling and a departure set their own
            // animation and keep it.
            .transaction(value: index) { transaction in
                if transaction.animation == nil, !reduceMotion {
                    transaction.animation = Self.settle.delay(Self.fadeDuration)
                }
            }
    }

    /// How far the front card has moved: with the finger at first, then rubber-banding so it never
    /// travels more than one card height. A lone request only pulls elastically, and an upward drag
    /// never more than `maxUpwardPull`.
    private func frontTravel(height: CGFloat) -> CGFloat {
        guard drag >= 0 else { return Self.upwardPull(drag) }
        guard items.count > 1 else { return sqrt(drag) * 2 }
        let knee = height * 0.7
        guard drag > knee else { return drag }
        let room = height - knee
        return knee + room * (1 - exp(-(drag - knee) / room))
    }

    /// The front card's offset for a vertical drag of `translation`, when it goes up: a small elastic
    /// pull that resists toward `maxUpwardPull`. Zero for a downward drag.
    static func upwardPull(_ translation: CGFloat) -> CGFloat {
        guard translation < 0 else { return 0 }
        return -maxUpwardPull * (1 - exp(translation / (maxUpwardPull * 3)))
    }

    private var cycleGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                // A short spring picks the cards up from wherever a release left them mid-flight.
                withAnimation(.interactiveSpring(duration: 0.15)) {
                    drag = value.translation.height
                }
            }
            .onEnded { value in
                let finishes = items.count > 1 && PaymentRequestDeckOrder.finishesCycle(
                    translation: value.translation.height,
                    predictedTranslation: value.predictedEndTranslation.height,
                    height: frontHeight
                )
                // Past the threshold the front card drops behind into the back slot as the rest
                // finish rising; short of it, everything springs back together.
                withAnimation(Self.settle) {
                    if finishes { state.order.cycle() }
                    drag = 0
                }
            }
    }
}

/// The parts of the front card measured in both states, so the moving card can lay each one out
/// between where it sits in the stack and where it sits in the expanded list.
enum DeckPart: Hashable {
    case container
    case ring
    case title
    case amounts
    /// The Pay button, which the moving card fades out on its way into the list and back in as it lands.
    case pay
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

/// A card in the stack: the ring, the title, and the status line, which reads "You owe <share> ·
/// <time left>" beside a Pay button while the viewer owes on it and the viewer status line otherwise.
struct PaymentRequestStackFace: View {

    let item: PaymentRequestDeckItem
    /// Stretches the card to the width it's offered, so a card in the stack matches the front one.
    var fillsWidth = false
    var measure: DeckPartMeasure? = nil
    var pay: ((PaymentRequestID) -> Void)? = nil

    static let ringDiameter: CGFloat = 32
    static let cornerRadius: CGFloat = 14
    /// The title's point size, which the expand morph scales from.
    static let titleSize: CGFloat = 14

    /// The card's second line: "You owe $5 · 2 days left" while owed, otherwise the viewer status line.
    @ViewBuilder
    static func amounts(_ item: PaymentRequestDeckItem) -> some View {
        if let share = item.owedShare {
            Text(PaymentRequestViewerStatus.owedLead(share) + AttributedString(" · \(item.timeLeft)"))
        } else {
            PaymentRequestViewerStatusLine(status: item.viewerStatus, amounts: item.amounts)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            PaymentRequestRing(fraction: item.card.fraction, isEnded: false, diameter: Self.ringDiameter)
                .paidBadge(item.viewerStatus.showsPaidBadge, diameter: Self.ringDiameter, isEnded: false)
            .deckPart(.ring, measure)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.card.title)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .deckPart(.title, measure)
                Self.amounts(item)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .deckPart(.amounts, measure)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
            if item.owedShare != nil {
                Button { pay?(item.id) } label: { PaymentRequestStackPayLabel() }
                    .buttonStyle(.plain)
                    .deckPart(.pay, measure)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(Color.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(item.owedShare != nil ? Color.success : Color.rowSeparator))
                .deckPart(.container, measure)
        }
        // The paid badge arriving fades in.
        .requestMotion(value: item.viewerStatus.showsPaidBadge)
    }
}

/// The stack's green Pay capsule.
private struct PaymentRequestStackPayLabel: View {
    var body: some View {
        Text("Pay")
            .font(.appTextSmall)
            .foregroundStyle(Color.backgroundMain)
            .padding(.horizontal, 18)
            .frame(height: 32)
            .background(Color.success, in: .capsule)
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
                PaymentRequestRing(fraction: item.card.fraction, isEnded: false, diameter: 36)
                    .paidBadge(item.viewerStatus.showsPaidBadge, diameter: 36, isEnded: false)
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
            PaymentRequestProgressBar(fraction: item.card.fraction, isEnded: false)
                .deckPart(.bar, measure)
            PaymentRequestDeckCardFooter(item: item)
                .deckPart(.status, measure)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.rowSeparator))
                .deckPart(.container, measure)
        }
        .accessibilityElement(children: .combine)
    }
}

/// An expanded card's footer: the time left, and the viewer's part of the status at the trailing end.
private struct PaymentRequestDeckCardFooter: View {

    let item: PaymentRequestDeckItem

    var body: some View {
        HStack(spacing: 8) {
            Text(item.card.statusLine)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let lead = item.viewerStatus.lead {
                Text(lead)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .font(.appTextCaption)
        .foregroundStyle(Color.textSecondary)
    }
}

// MARK: - Expanded -

/// The expanded deck: every request as a full-width card beneath the app bar. `PaymentRequestDeckWindow`
/// puts it over the chat's backdrop.
/// While it opens or closes, `PaymentRequestDeckMorph` draws the front card between the stack and
/// the list.
struct PaymentRequestDeckOverlay: View {

    let items: [PaymentRequestDeckItem]
    @Bindable var state: PaymentRequestDeckState
    let open: (PaymentRequestID) -> Void

    @State private var origin: CGPoint = .zero
    @State private var cardHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            list
            if let front = items.first {
                // Kept mounted and hidden at rest: inserted in the same update that starts a collapse,
                // it would have no starting value to animate from and jump straight to the stack.
                PaymentRequestDeckMorph(
                    item: front,
                    progress: state.progress,
                    stack: state.stackFrames,
                    card: state.cardFrames,
                    stackTypeSize: state.stackTypeSize,
                    origin: origin
                )
                .opacity(state.isSettled ? 0 : 1)
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

            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            // The scroll view covers the backdrop, so the space below the cards takes the backdrop's
            // tap; the cards' own buttons win over it.
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

/// The front card part way between the stack (`progress` 0) and the expanded list (1), laid out from
/// both states' measured frames so it lands exactly on either. Text the two share moves and scales
/// across; the expanded card's own lines ride inside the container and fade in over the last 40%.
private struct PaymentRequestDeckMorph: View, Animatable {

    let item: PaymentRequestDeckItem
    var progress: CGFloat
    let stack: [DeckPart: CGRect]
    let card: [DeckPart: CGRect]
    let stackTypeSize: DynamicTypeSize
    let origin: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let cardRing: CGFloat = 36
    /// appTextMedium over the collapsed title's size.
    private var titleScale: CGFloat { 16 / PaymentRequestStackFace.titleSize }
    /// appTextSmall over appTextCaption, the amounts' two sizes.
    private static let amountsScale: CGFloat = 14 / 12

    var body: some View {
        let p = min(max(progress, 0), 1)
        if let stackBox = stack[.container], let cardBox = card[.container] {
            let box = lerp(stackBox, cardBox, p)
            // The title reads the same in both, so its two sizes cross over the whole move. The
            // amounts read differently, so one leaves before the other arrives rather than overlap.
            let outgoing = 1 - p * p
            let incoming = 1 - (1 - p) * (1 - p)
            let amountsOut = max(0, 1 - p / 0.35)
            let amountsIn = min(1, max(0, (p - 0.35) / 0.3))
            let extras = max(0, (p - 0.6) / 0.4)

            let radius = PaymentRequestStackFace.cornerRadius + (12 - PaymentRequestStackFace.cornerRadius) * p
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color.backgroundSecondary)
                    .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.rowSeparator))
                    .overlay {
                        if item.owedShare != nil {
                            RoundedRectangle(cornerRadius: radius).strokeBorder(Color.success).opacity(1 - p)
                        }
                    }
                    .place(box, origin)

                Group {
                    ring(p)
                    stackPay(in: box, from: stackBox, opacity: amountsOut)
                    shared(.title, scale: titleScale, p: p, outgoing: outgoing, incoming: incoming) { isCard in
                        Text(item.card.title)
                            .font(isCard ? .appTextMedium : .appTextSmall)
                            .foregroundStyle(Color.textMain)
                            .lineLimit(isCard ? 2 : 1)
                    }
                    shared(.amounts, scale: Self.amountsScale, p: p, outgoing: amountsOut, incoming: amountsIn) { isCard in
                        Group {
                            if isCard {
                                Text(item.card.progressLine)
                            } else {
                                PaymentRequestStackFace.amounts(item)
                            }
                        }
                        .font(isCard ? .appTextSmall : .appTextCaption)
                        .foregroundStyle(isCard ? Color.textMain : Color.textSecondary)
                        .lineLimit(1)
                    }
                    Group {
                        extra(.label, in: box, from: cardBox) {
                            Text("Request").font(.appTextCaption).foregroundStyle(Color.textSecondary)
                        }
                        extra(.bar, in: box, from: cardBox, stretches: true) {
                            PaymentRequestProgressBar(fraction: item.card.fraction, isEnded: false)
                        }
                        extra(.status, in: box, from: cardBox, stretches: true) {
                            PaymentRequestDeckCardFooter(item: item)
                        }
                    }
                    .opacity(extras)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The ring at its size part way between the two, drawn from whichever end is nearer so its "$"
    /// keeps the right weight.
    @ViewBuilder
    private func ring(_ p: CGFloat) -> some View {
        if let from = stack[.ring], let to = card[.ring] {
            let frame = lerp(from, to, p)
            let base = p < 0.5 ? PaymentRequestStackFace.ringDiameter : Self.cardRing
            PaymentRequestRing(fraction: item.card.fraction, isEnded: false, diameter: base)
                .paidBadge(item.viewerStatus.showsPaidBadge, diameter: base, isEnded: false)
            .scaleEffect(frame.width / base)
            .frame(width: base, height: base)
            .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
        }
    }

    /// A part both states show: the stack's version scales up and fades out while the card's scales
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
        if let from = stack[part], let to = card[part] {
            let corner = CGPoint(x: from.minX + (to.minX - from.minX) * p - origin.x, y: from.minY + (to.minY - from.minY) * p - origin.y)
            let grow = 1 + (scale - 1) * p
            // A point over the measured width: laid out at exactly its own fractional width, the face's
            // text can round down and truncate.
            text(false)
                .dynamicTypeSize(stackTypeSize)
                .frame(width: from.width + 1, height: from.height, alignment: .topLeading)
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

    /// The Pay button, held the same distance from the moving container's trailing edge so it
    /// is in place before the card lands, rather than appearing a frame after it.
    @ViewBuilder
    private func stackPay(in box: CGRect, from stackBox: CGRect, opacity: CGFloat) -> some View {
        if item.owedShare != nil, let rest = stack[.pay] {
            PaymentRequestStackPayLabel()
                .dynamicTypeSize(stackTypeSize)
                .frame(width: rest.width, height: rest.height)
                .offset(x: box.maxX - (stackBox.maxX - rest.minX) - origin.x, y: box.minY + (rest.minY - stackBox.minY) - origin.y)
                .opacity(opacity)
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
        viewer: UserID?,
        order: PaymentRequestDeckOrder,
        copy: PaymentRequestCopy,
        now: Date
    ) -> [PaymentRequestDeckItem] {
        order.apply(to: deck(for: conversationID, viewer: viewer, at: now)).compactMap { request in
            deckItem(request, viewer: viewer, copy: copy, now: now)
        }
    }

    /// The deck card for `id` once it has completed, for its ring's last sweep on the way out; nil
    /// when it isn't held, didn't complete, or its title can't be read.
    func completedDeckItem(_ id: PaymentRequestID, viewer: UserID?, copy: PaymentRequestCopy, now: Date) -> PaymentRequestDeckItem? {
        guard let request = request(id), request.status == .completed else { return nil }
        return deckItem(request, viewer: viewer, copy: copy, now: now)
    }

    private func deckItem(_ request: GroupPaymentRequest, viewer: UserID?, copy: PaymentRequestCopy, now: Date) -> PaymentRequestDeckItem? {
        guard let text = text(of: request) else { return nil }
        let owed = viewer.flatMap { viewer in
            request.isOwed(by: viewer, at: now) ? request.share(for: viewer) : nil
        }
        let deadline = request.deadline(at: now)
        return PaymentRequestDeckItem(
            request: request,
            card: PaymentRequestCardContent(request: request, title: text.title, copy: copy, now: now),
            amounts: copy.deckAmounts(request),
            viewerStatus: PaymentRequestViewerStatus(request: request, viewer: viewer, copy: copy),
            owedShare: owed.map { copy.shareText($0, of: request) },
            timeLeft: PaymentRequestCopy.timeLeft(deadline)
        )
    }
}
