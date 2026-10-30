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
    /// The front card's parts in global coordinates in each collapsed face, and in the expanded list.
    var faceFrames: [PaymentRequestDeckStyle: [DeckPart: CGRect]] = [:]
    var cardFrames: [DeckPart: CGRect] = [:]
    /// The front card's parts in the face the deck collapses into.
    var pillFrames: [DeckPart: CGRect] { faceFrames[source] ?? [:] }
    /// The app-bar pill's frame, where the expanded deck's close button sits whichever face it opened from.
    var barFrame: CGRect? { faceFrames[.pill]?[.container] }
    /// Each collapsed face's Dynamic Type size. The toolbar can lay its text out at a different size
    /// than the overlay, so the moving copy draws the face's text at its own size to land on it exactly.
    var faceTypeSizes: [PaymentRequestDeckStyle: DynamicTypeSize] = [:]
    /// The Dynamic Type size of the face the deck collapses into.
    var pillTypeSize: DynamicTypeSize { faceTypeSizes[source] ?? .large }
    /// The face the deck collapses into, so the moving card starts from it and lands back on it.
    var source: PaymentRequestDeckStyle = .pill
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

    /// Puts the front card back at the pill with no animation, for when the deck is hidden behind a
    /// screen. The overlay stays up, drawing the card where the pill is, until `endPresentation()`.
    func snapToPill() {
        guard isOpen else { return }
        isOpen = false
        isSettled = false
        generation += 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { progress = 0 }
    }

    /// Takes the overlay down once the card rests at the pill, handing back to the pill itself.
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

/// Whether the pill is in the app bar, and how far it has faded in. It fades in and out in place
/// when requests arrive or run out after the chat is on screen, and is simply there when the chat
/// opens with requests already known.
@MainActor
@Observable
final class PaymentRequestPillPresence {

    /// The toolbar item exists; it outlives `isVisible` by the fade-out.
    private(set) var isInBar = false
    /// Drives the pill's opacity and scale, and the room the title leaves for it.
    private(set) var isVisible = false
    /// The last non-empty deck, drawn while the pill fades out after the requests are gone.
    private(set) var lastItems: [PaymentRequestDeckItem] = []

    /// The pill fades in when it first shows rather than being there from its first frame.
    private(set) var fadesIn = false
    private var hasSettled = false

    static let fade = Animation.easeOut(duration: 0.25)

    /// The items the pill draws: the live deck, or the last one while it fades out.
    func items(_ live: [PaymentRequestDeckItem]) -> [PaymentRequestDeckItem] {
        live.isEmpty ? lastItems : live
    }

    /// Follows the deck's contents; the first call sets the state without a fade.
    func update(_ items: [PaymentRequestDeckItem]) {
        if !items.isEmpty { lastItems = items }
        let hasItems = !items.isEmpty
        guard hasSettled else {
            hasSettled = true
            isInBar = hasItems
            isVisible = hasItems
            return
        }
        guard hasItems != isVisible else { return }
        if hasItems {
            // The toolbar builds the item's view on its own schedule, so the pill runs its own
            // fade once it appears; this animation only moves the title out of its way.
            fadesIn = true
            isInBar = true
            withAnimation(Self.fade) { isVisible = true }
        } else {
            withAnimation(Self.fade) {
                isVisible = false
            } completion: { [weak self] in
                guard let self, !self.isVisible else { return }
                self.isInBar = false
                self.lastItems = []
            }
        }
    }
}

/// Fades and scales the pill in place as `presence` shows and hides it.
struct PaymentRequestPillAppearance: ViewModifier {

    let presence: PaymentRequestPillPresence
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
                withAnimation(PaymentRequestPillPresence.fade) { hasAppeared = true }
            }
    }
}

// MARK: - Strip collapse -

/// How far the owed strip has shrunk into the app-bar pill, following the reader's scroll away
/// from the newest messages until it has shrunk all the way, then pinned there for the visit.
@MainActor
@Observable
final class PaymentRequestStripCollapse {
    /// 0 with the strip fully out under the bar, 1 with it fully shrunk into the pill.
    private(set) var progress: CGFloat = 0
    /// Whether the collapsed deck reads as the pill. Flips past the middle of the collapse, with a
    /// band either side so a small scroll back and forth never flaps it.
    private(set) var isScrolledAway = false
    /// Whether the strip has shrunk all the way into the pill, after which scrolling no longer moves it.
    private(set) var isPinned = false

    /// The strip's slot under the bar and the pill's in it, in global space, where the collapse
    /// carries the one onto the other.
    var stripFrame: CGRect = .zero
    var pillFrame: CGRect = .zero

    /// Points scrolled away from the newest messages over which the strip shrinks into the pill.
    static let distance: CGFloat = 140

    /// How far the moving strip has handed over to the pill, 0 to 1: it does so over the last part
    /// of the move, once their bounds nearly agree.
    static func handover(_ progress: CGFloat) -> CGFloat {
        min(max((progress - 0.6) / 0.4, 0), 1)
    }
    private static let awayAt: CGFloat = 0.65
    private static let backAt: CGFloat = 0.35

    /// Follows the reader `distanceFromNewest` points above the newest messages.
    func update(distanceFromNewest: CGFloat) {
        move(to: distanceFromNewest / Self.distance)
    }

    /// Follows a swipe up on the strip that has covered `fraction` of the way into the pill.
    func dock(following fraction: CGFloat) {
        move(to: fraction)
    }

    /// Ends a swipe up on the strip: past halfway it docks into the pill for the rest of the visit,
    /// short of that it springs back out.
    func endDock(at fraction: CGFloat) {
        move(to: fraction >= 0.5 ? 1 : 0)
    }

    private func move(to fraction: CGFloat) {
        guard !isPinned else { return }
        let next = min(max(fraction, 0), 1)
        if abs(next - progress) > 0.001 || (next != progress && (next == 0 || next == 1)) {
            progress = next
        }
        if !isScrolledAway, next >= Self.awayAt {
            isScrolledAway = true
        } else if isScrolledAway, next <= Self.backAt {
            isScrolledAway = false
        }
        if next >= 1 - 0.001 {
            progress = 1
            isScrolledAway = true
            isPinned = true
        }
    }

    /// Brings the strip back out under the bar, for a request the viewer newly owes on.
    func unpin() {
        isPinned = false
        isScrolledAway = false
        progress = 0
    }
}

/// Carries the owed strip into the app-bar pill as one stack as `collapse` runs: its bounds move
/// and shrink from the strip's slot onto the pill's, then it hands over to the pill in place. It
/// stops taking touches once it is mostly the pill's.
struct PaymentRequestStripCollapseEffect: ViewModifier {
    let collapse: PaymentRequestStripCollapse

    func body(content: Content) -> some View {
        let progress = collapse.progress
        let morph = Morph(from: collapse.stripFrame, to: collapse.pillFrame, progress: progress)
        content
            // The strip lays out at the width that, once scaled, spans the moving bounds, so its
            // text stays upright instead of squeezing.
            .frame(width: progress > 0 ? morph?.layoutWidth : nil, alignment: .leading)
            .environment(\.paymentRequestStripCollapse, progress)
            .scaleEffect(morph?.scale ?? 1, anchor: .topLeading)
            .offset(morph?.offset ?? .zero)
            // One layer, so the cards beneath never show through the front one as it fades.
            .compositingGroup()
            .opacity(1 - PaymentRequestStripCollapse.handover(progress))
            .modifier(StripSlot())
            .allowsHitTesting(progress < 0.5)
            .accessibilityHidden(progress >= 0.5)
    }

    /// The strip's bounds partway onto the pill's, as a layout width plus a scale and offset that
    /// leave its layout slot alone. Nil until both have been measured.
    private struct Morph {
        let layoutWidth: CGFloat
        let scale: CGFloat
        let offset: CGSize

        init?(from strip: CGRect, to pill: CGRect, progress: CGFloat) {
            guard strip.height > 0, strip.width > 0, pill.height > 0, pill.width > 0 else { return nil }
            let endScale = pill.height / strip.height
            scale = 1 + (endScale - 1) * progress
            layoutWidth = strip.width + (pill.width / endScale - strip.width) * progress
            offset = CGSize(
                width: (pill.minX - strip.minX) * progress,
                height: (pill.minY - strip.minY) * progress
            )
        }
    }
}

/// Takes the width it's offered whatever the moving strip inside lays out at, so the slot measured
/// around it never follows the strip's own width back into the morph.
private struct StripSlot: ViewModifier {
    func body(content: Content) -> some View {
        StripSlotLayout { content }
    }
}

private struct StripSlotLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let child = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: proposal.width ?? child.width, height: child.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }
}

/// Fades the app-bar pill in as the strip hands over to it at the end of `collapse`.
struct PaymentRequestPillRevealEffect: ViewModifier {
    let collapse: PaymentRequestStripCollapse
    let isBehindStrip: Bool

    func body(content: Content) -> some View {
        content
            .compositingGroup()
            .opacity(isBehindStrip ? PaymentRequestStripCollapse.handover(collapse.progress) : 1)
    }
}

extension EnvironmentValues {
    /// How far the strip around this view has shrunk into the pill, 0 to 1.
    @Entry var paymentRequestStripCollapse: CGFloat = 0
}

// MARK: - Style -

/// Where the collapsed deck sits: the app-bar pill, or the strip under the bar while the viewer
/// owes and reads the newest messages.
enum PaymentRequestDeckStyle: Hashable {
    case pill
    case strip

    /// The style for a deck the viewer `owes` on: the strip shrinks into the pill while they read
    /// older messages, and grows back at the newest.
    static func collapsed(owes: Bool, isScrolledAway: Bool) -> PaymentRequestDeckStyle {
        owes && !isScrolledAway ? .strip : .pill
    }

    var ringDiameter: CGFloat {
        switch self {
        case .pill: 26
        case .strip: 32
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .pill: 18
        case .strip: 14
        }
    }

    /// The title's font and its point size, which the expand morph scales from.
    var titleFont: Font {
        switch self {
        case .pill: .appTextCaption
        case .strip: .appTextSmall
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .pill: 12
        case .strip: 14
        }
    }

    /// The face's second line: "You owe $5 · 2 days left" on the strip while owed, otherwise the
    /// viewer status line.
    @ViewBuilder
    func amounts(_ item: PaymentRequestDeckItem) -> some View {
        if self == .strip, let share = item.owedShare {
            Text(PaymentRequestViewerStatus.owedLead(share) + AttributedString(" · \(item.timeLeft)"))
        } else {
            PaymentRequestViewerStatusLine(status: item.viewerStatus, amounts: item.amounts)
        }
    }
}

// MARK: - Pill -

/// The collapsed deck (concept B): the front request with up to two more peeking beneath it, as a
/// stack of cards, in the app bar or as the strip under it. Swipe down cycles; tap expands.
struct PaymentRequestPill: View {

    let items: [PaymentRequestDeckItem]
    var style: PaymentRequestDeckStyle = .pill
    let accessibilityLabel: String
    @Bindable var state: PaymentRequestDeckState
    /// Starts paying the viewer's share of a request, from the strip's Pay button.
    var pay: ((PaymentRequestID) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The finger's downward travel, not the front card's: the card rubber-bands past one pill height.
    @State private var drag: CGFloat = 0
    @State private var frontHeight: CGFloat = 43

    private static let peekStep: CGFloat = 5
    /// How much each step back shrinks a card, so its sides tuck in under the one in front.
    private static let depthScale: CGFloat = 0.08
    private static let depthDim: CGFloat = 0.25
    private static let settle = Animation.spring(duration: 0.35, bounce: 0.15)
    /// How long the ended look takes to fade in, which a re-sort waits out.
    private static let endedFadeDuration = 0.3

    var body: some View {
        // The front request at rest sets the pill's size and is what the deck measures; the cards
        // drawn over it move freely without feeding back into the bar's layout.
        ZStack(alignment: .top) {
            if let front = items.first {
                PaymentRequestPillFace(item: front, style: style, measure: report)
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
        .onChange(of: typeSize, initial: true) { state.faceTypeSizes[style] = typeSize }
        .onChange(of: style) { state.faceTypeSizes[style] = typeSize }
        .contentShape(Rectangle())
        .onTapGesture { state.expand() }
        .gesture(cycleGesture)
        .accessibilityRepresentation {
            Button(accessibilityLabel) { state.expand() }
                .accessibilityAction(named: "Next request") {
                    guard items.count > 1 else { return }
                    withAnimation(Self.settle) { state.order.cycle() }
                }
            if style == .strip, let front = items.first, let share = front.owedShare, let pay {
                Button("Pay \(share)") { pay(front.id) }
            }
        }
    }

    /// `item` at `index` in the deck: the front card follows the finger, and each card behind rises
    /// a step toward the front as the drag nears one pill height. Past the second card they stack
    /// in the back slot, so a card sent to the back slides up under the others.
    /// Records a part of the front card for the expand morph under this face, so a face animating
    /// out of view can't overwrite the one the deck collapses into.
    private func report(_ part: DeckPart, _ frame: CGRect) {
        state.faceFrames[style, default: [:]][part] = frame
    }

    private func card(_ item: PaymentRequestDeckItem, at index: Int) -> some View {
        let height = max(frontHeight, 1)
        let rise = items.count > 1 ? min(1, drag / height) : 0
        let depth = index == 0 ? 0 : min(max(0, CGFloat(index) - rise), 2)
        let scale = index == 0 ? 1 - Self.depthScale * 0.5 * rise : 1 - Self.depthScale * depth
        // Anchored at the top, a card's scaled bottom sits a peek step lower per step back.
        let offset = index == 0 ? frontTravel(height: height) : height * (1 - scale) + Self.peekStep * depth
        return PaymentRequestPillFace(item: item, style: style, fillsWidth: true, pay: pay)
            .overlay {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(Color.backgroundMain.opacity(Self.depthDim * depth))
                    .allowsHitTesting(false)
            }
            .scaleEffect(scale, anchor: .top)
            .offset(y: offset)
            // The moving copy stands in for the front card until it lands back here.
            .opacity(index == 0 && state.source == style && state.phase != .collapsed ? 0 : 1)
            // Only the front card's Pay button takes a tap; the rest peek.
            .allowsHitTesting(index == 0)
            .zIndex(Double(items.count - index))
            // A move that no gesture drives, such as a request ending and sorting down, settles after
            // the ended look has faded. Cycling sets its own animation and keeps it.
            .transaction(value: index) { transaction in
                if transaction.animation == nil, !reduceMotion {
                    transaction.animation = Self.settle.delay(Self.endedFadeDuration)
                }
            }
    }

    /// How far the front card has moved: with the finger at first, then rubber-banding so it never
    /// travels more than one pill height. A lone request only pulls elastically.
    private func frontTravel(height: CGFloat) -> CGFloat {
        guard items.count > 1 else { return sqrt(drag) * 2 }
        let knee = height * 0.7
        guard drag > knee else { return drag }
        let room = height - knee
        return knee + room * (1 - exp(-(drag - knee) / room))
    }

    private var cycleGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                // A short spring picks the cards up from wherever a release left them mid-flight.
                withAnimation(.interactiveSpring(duration: 0.15)) {
                    drag = max(0, value.translation.height)
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
/// between where it sits in the pill and where it sits in the expanded list.
enum DeckPart: Hashable {
    case container
    case ring
    case title
    case amounts
    /// The strip's Pay button, which the moving card fades out on its way into the list and back in as it lands.
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

/// A card in the collapsed deck: the ring, the title and "<paid> of <requested>" in the pill, and on
/// the strip, the owed line with a Pay button.
struct PaymentRequestPillFace: View {

    let item: PaymentRequestDeckItem
    var style: PaymentRequestDeckStyle = .pill
    /// Stretches the card to the width it's offered, so a card in the stack matches the front one.
    var fillsWidth = false
    var measure: DeckPartMeasure? = nil
    var pay: ((PaymentRequestID) -> Void)? = nil

    @Environment(\.paymentRequestStripCollapse) private var stripCollapse

    var body: some View {
        Group {
            switch style {
            case .pill: pill
            case .strip: strip
            }
        }
        // The switch to the ended look fades, and so does the paid badge arriving.
        .requestMotion(value: item.card.isEnded)
        .requestMotion(value: item.viewerStatus.showsPaidBadge)
    }

    private var ring: some View {
        PaymentRequestRing(
            fraction: item.card.fraction,
            isEnded: item.card.isEnded,
            isClosed: item.request.status == .closed,
            diameter: style.ringDiameter
        )
        .paidBadge(item.viewerStatus.showsPaidBadge, diameter: style.ringDiameter, isEnded: item.card.isEnded)
        .deckPart(.ring, measure)
    }

    private var pill: some View {
        HStack(spacing: 8) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                Text(item.card.title)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                    .deckPart(.title, measure)
                style.amounts(item)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .deckPart(.amounts, measure)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 90, alignment: .leading)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
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

    private var strip: some View {
        HStack(spacing: 12) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                Text(item.card.title)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .deckPart(.title, measure)
                style.amounts(item)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .deckPart(.amounts, measure)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
            if item.owedShare != nil {
                Button { pay?(item.id) } label: { PaymentRequestStripPayLabel() }
                    .buttonStyle(.plain)
                    .deckPart(.pay, measure)
                    .opacity(max(0, 1 - 2 * Double(stripCollapse)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(item.card.isEnded ? 0.4 : 1)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(item.owedShare != nil ? Color.success : Color.rowSeparator))
                .opacity(item.card.isEnded ? 0.4 : 1)
                .background(Color.backgroundMain, in: .rect(cornerRadius: 14))
                .deckPart(.container, measure)
        }
    }
}

/// The strip's green Pay capsule.
private struct PaymentRequestStripPayLabel: View {
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
                PaymentRequestRing(fraction: item.card.fraction, isEnded: item.card.isEnded, isClosed: item.request.status == .closed, diameter: 36)
                    .paidBadge(item.viewerStatus.showsPaidBadge, diameter: 36, isEnded: item.card.isEnded)
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
            PaymentRequestDeckCardFooter(item: item)
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
            list
            if let front = items.first {
                // Kept mounted and hidden at rest: inserted in the same update that starts a collapse,
                // it would have no starting value to animate from and jump straight to the pill.
                PaymentRequestDeckMorph(
                    item: front,
                    progress: state.progress,
                    pill: state.pillFrames,
                    card: state.cardFrames,
                    pillTypeSize: state.pillTypeSize,
                    source: state.source,
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

/// The front card part way between the pill (`progress` 0) and the expanded list (1), laid out from
/// both states' measured frames so it lands exactly on either. Text the two share moves and scales
/// across; the expanded card's own lines ride inside the container and fade in over the last 40%.
private struct PaymentRequestDeckMorph: View, Animatable {

    let item: PaymentRequestDeckItem
    var progress: CGFloat
    let pill: [DeckPart: CGRect]
    let card: [DeckPart: CGRect]
    let pillTypeSize: DynamicTypeSize
    /// The collapsed face the card moves from and back to.
    let source: PaymentRequestDeckStyle
    let origin: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let cardRing: CGFloat = 36
    /// appTextMedium over the collapsed title's size.
    private var titleScale: CGFloat { 16 / source.titleSize }
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

            let radius = source.cornerRadius + (12 - source.cornerRadius) * p
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color.backgroundSecondary)
                    .opacity(item.card.isEnded ? 0.4 + 0.6 * p : 1)
                    .background(Color.backgroundMain, in: .rect(cornerRadius: radius))
                    .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.rowSeparator))
                    .overlay {
                        if source == .strip, item.owedShare != nil {
                            RoundedRectangle(cornerRadius: radius).strokeBorder(Color.success).opacity(1 - p)
                        }
                    }
                    .place(box, origin)

                Group {
                    ring(p)
                    stripPay(in: box, from: pillBox, opacity: amountsOut)
                    shared(.title, scale: titleScale, p: p, outgoing: outgoing, incoming: incoming) { isCard in
                        Text(item.card.title)
                            .font(isCard ? .appTextMedium : source.titleFont)
                            .foregroundStyle(Color.textMain)
                            .lineLimit(isCard ? 2 : 1)
                    }
                    shared(.amounts, scale: Self.amountsScale, p: p, outgoing: amountsOut, incoming: amountsIn) { isCard in
                        Group {
                            if isCard {
                                Text(item.card.progressLine)
                            } else {
                                source.amounts(item)
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
                            PaymentRequestProgressBar(fraction: item.card.fraction, isEnded: item.card.isEnded)
                        }
                        extra(.status, in: box, from: cardBox, stretches: true) {
                            PaymentRequestDeckCardFooter(item: item)
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
            let base = p < 0.5 ? source.ringDiameter : Self.cardRing
            PaymentRequestRing(
                fraction: item.card.fraction,
                isEnded: item.card.isEnded,
                isClosed: item.request.status == .closed,
                diameter: base
            )
            .paidBadge(item.viewerStatus.showsPaidBadge, diameter: base, isEnded: item.card.isEnded)
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
            // A point over the measured width: laid out at exactly its own fractional width, the face's
            // text can round down and truncate.
            text(false)
                .dynamicTypeSize(pillTypeSize)
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

    /// The strip's Pay button, held the same distance from the moving container's trailing edge so it
    /// is in place before the card lands, rather than appearing a frame after it.
    @ViewBuilder
    private func stripPay(in box: CGRect, from pillBox: CGRect, opacity: CGFloat) -> some View {
        if source == .strip, item.owedShare != nil, let rest = pill[.pay] {
            PaymentRequestStripPayLabel()
                .dynamicTypeSize(pillTypeSize)
                .frame(width: rest.width, height: rest.height)
                .offset(x: box.maxX - (pillBox.maxX - rest.minX) - origin.x, y: box.minY + (rest.minY - pillBox.minY) - origin.y)
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
}
