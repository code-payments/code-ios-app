//
//  ConversationBottomBar.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Shared state for the unified bottom bar: the focus-driven `isComposing` flag that drives the
/// Send Cash morph and the screen's interactive-dismiss gate. The draft itself lives in
/// `ComposerModel`, which also knows whether it is a new message or an edit.
@MainActor @Observable final class ConversationBarModel {
    var isComposing = false
}

/// Single spring driving the whole bar: the button morph, the composer's
/// appearance when the chat materializes, and the send-arrow pop.
private let barMorphSpring = ChatMotion.swap.animation

/// The curve the bar grows and shrinks on around the reply strip.
///
/// Separate from `barMorphSpring` because `swap` overshoots, and the transcript's bottom inset
/// tracks this height every frame — a bar that overshoots drags the messages past their resting
/// place and back.
private let replySpring = ChatMotion.replySurface.animation

/// Metrics shared by the field, the button beside it, and the reply quote above them, so their
/// heights and corners can't desync. Deliberately not `Metrics.buttonHeight`/`buttonRadius` — beside
/// the field the controls are field-sized, not standard-button-sized.
enum BarMetrics {
    static let fieldMinHeight: CGFloat = 34
    static let fieldVerticalPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 14
    /// The height of every bar control: a single-line field plus its padding, and the height the
    /// Send Cash button morphs at while there is a composer beside it.
    static let contentHeight: CGFloat = fieldMinHeight + fieldVerticalPadding * 2
    /// The bar's own margin around its controls, above and below.
    static let contentPadding: CGFloat = 8
    /// The margin between the bar's controls and the screen's sides while the keyboard is up.
    static let edgeInset: CGFloat = 12
    /// How far into the home indicator's safe area the compact bar rests while the keyboard is down.
    static let compactDrop: CGFloat = 8
    /// The margin between the compact bar's controls and the screen's sides.
    static let compactInset: CGFloat = 32
}

/// The unified bottom bar: Send Cash (morphing) beside the message field.
/// A standard-size filled Send Cash alone until the chat exists server-side.
struct ConversationBottomBar: View {

    let showsSendCash: Bool
    let chatExists: Bool
    let conversationID: ConversationID?
    let symbol: String
    let onSendCash: () -> Void
    let model: ConversationBarModel
    let composer: ComposerModel
    /// Whether this is a tip DM, whose Send Cash reads Start Chatting until the chat exists.
    var isTipDm: Bool = false
    /// What the first tip has to clear to open this chat, named on the CTA.
    /// Nil once the chat exists, and when no floor has resolved yet.
    var startChattingFee: FiatAmount? = nil
    /// Whether the chat's participation rules leave this user anything to type. Anything but
    /// ``ConversationGatePresentation/open`` replaces the whole composer with the gate panel.
    var gate: ConversationGatePresentation = .open
    /// Display name of the mint the gate's requirement names, once resolved. See
    /// ``ConversationGatePanel``.
    var gateMintName: String? = nil
    /// Opens the buy or add-cash flow from the gate panel's CTA.
    var onGateAddFunds: () -> Void = {}
    /// Joins the chat from the gate panel's Join button.
    var onGateJoin: () -> Void = {}
    /// Whether a join is in flight, so the gate panel's button can stop taking taps.
    var isJoiningChat: Bool = false
    /// The group's mention picker. `nil` in a DM, which never offers one.
    var mentions: MentionPickerModel? = nil

    /// The results the mention list draws: the model's, taken in through `onChange` so a new search
    /// replacing an open list can land inside one animation that covers the whole bar.
    @State private var listedCandidates: [ConversationMember] = []
    /// The reply as the bar draws it. Under an open mention list it changes in one transaction, so
    /// the strip and the list's row cap move on one spring; elsewhere it is the composer's own.
    @State private var listedReply: ComposerModel.ReplyTarget?

    /// The composer row's measured height, reported as part of what the mention list's room is
    /// measured without.
    @State private var composerRowHeight: CGFloat = 0

    /// The curve the bar narrows and widens on as the keyboard goes and comes.
    private static let widthSpring = Animation.spring(duration: 0.22, bounce: 0.14)

    /// Whether the bar sits inset from the screen's sides: at rest with the keyboard down. It widens
    /// to the full edge inset as the keyboard comes up. Only once there is a composer; the pre-chat
    /// CTA keeps its full-width button.
    private var isCompact: Bool { chatExists && !model.isComposing }

    /// How much further in than ``BarMetrics/edgeInset`` the controls and the reply quote sit.
    private var compactExtraInset: CGFloat { isCompact ? BarMetrics.compactInset - BarMetrics.edgeInset : 0 }

    var body: some View {
        // The gate panel takes the bar whole rather than sitting inside it: none of the composer's
        // springs key on state a gated user can change.
        switch gate {
        case .undetermined:
            // Nothing is drawn at all until the rules land. A composer would be an affordance the
            // server may refuse, and a panel would have to name a requirement we haven't been told.
            // The bar arriving with the metadata is the honest version of both.
            EmptyView()

        case .join, .blocked, .readOnly:
            ConversationGatePanel(
                presentation: gate,
                mintName: gateMintName,
                onAddFunds: onGateAddFunds,
                onJoin: onGateJoin,
                isJoining: isJoiningChat
            )

        case .open:
            composerBar
        }
    }

    private var composerBar: some View {
        // Bottom-aligned, against the bar's own pinned bottom: the field is the side that grows, and
        // top-aligning the control beside it made the control travel with every line the draft
        // gained or lost. Nothing animates that travel — the bar's springs key on `chatExists` and
        // `isEditing`, neither of which moves during a send — so it snapped while the bar's height
        // sprang underneath it.
        let content = HStack(alignment: .bottom, spacing: 10) {
            // An edit takes over the bar: the leading control becomes the way out of it and Send
            // Cash steps aside until it resolves, the way WhatsApp hides its accessory controls.
            if composer.isEditing {
                CancelEditButton { composer.endEditing() }
            } else if showsSendCash {
                SendCashMorphButton(
                    symbol: symbol,
                    // Minimized by a reply as well as by focus. Starting a reply from the context
                    // menu raises the keyboard, and focus — and so `isComposing` — arrives a
                    // transaction later than the reply target, on its own bouncy spring: the button
                    // collapsed after the bar had already grown, jolting the field beside it.
                    // Reading the target directly puts the morph in the reply's own transaction, so
                    // the two move together and the later focus change finds nothing left to do.
                    composing: model.isComposing || composer.replyTarget != nil,
                    standalone: !chatExists,
                    // Every chat sits minimized beside its composer, but before
                    // the first tip there is no composer to sit beside: the
                    // design draws the full-width "Start Chatting" CTA
                    // (node 10074:18891).
                    alwaysMinimized: chatExists,
                    expandedTitle: isTipDm ? startChattingTitle : nil,
                    action: onSendCash
                )
            }
            if chatExists {
                ConversationComposer(conversationID: conversationID, model: model, composer: composer)
                    .transition(.opacity)
            }
        }
        // The Send Cash button morphs on the reply's spring. Inside the row's padding, so it covers
        // the button and the field beside it but not where the row sits: animated there, the row
        // slid from its old place every time a card opened above it and moved it down the stack.
        .animation(replySpring, value: composer.replyTarget)
        .padding(.horizontal, BarMetrics.edgeInset)
        .padding(.horizontal, compactExtraInset)
        .animation(Self.widthSpring, value: isCompact)
        .padding(.top, BarMetrics.contentPadding)
        .padding(.bottom, BarMetrics.contentPadding)
        .animation(barMorphSpring, value: chatExists)
        .animation(barMorphSpring, value: composer.isEditing)

        // No shared GlassEffectContainer: the composer's glass is a background
        // layer behind an editable text field, and a container composites its
        // glass above sibling content — drawing the glass over the typed text.
        // The Send Cash button and the field are separate pills 10pt apart, so
        // they don't need to sample each other.
        return VStack(spacing: 0) {
            BarCardGlassContainer {
            // The list rides the reply strip's reveal: same clip travel in, same fade out.
            // Under an open reply the list grows out of the strip's glass rather than under the clip.
            AccessoryReveal(kind: .mentions, item: mentionCandidates, collapsesInPlace: barReply != nil) { candidates in
                MentionSuggestionList(
                    candidates: candidates,
                    maxRows: MentionRowCap.rows(
                        replyOpen: replyOpen,
                        room: mentions?.room,
                        rowHeight: MentionListMetrics.rowHeight,
                        divider: MentionListMetrics.dividerHeight,
                        chrome: MentionListMetrics.chrome(replyOpen: replyOpen)
                    ),
                    replyOpen: replyOpen
                ) { member in
                    guard let username = member.username else { return }
                    composer.insertMention(username: username.value)
                }
            }
            .padding(.horizontal, compactExtraInset)
            .animation(Self.widthSpring, value: isCompact)
            // No `withAnimation` at the dismiss site either: the `.animation(_, value:)` below
            // already drives this state in both directions, and wrapping the dismissal in a second
            // transaction gave the exit a curve the entry never had.
            AccessoryReveal(kind: .reply, item: barReply, collapsesInPlace: mentionCandidates != nil) { target in
                ComposerReplyStrip(target: target) { composer.endReplying() }
            }
                // The quote narrows with the row below it, so the two keep one margin.
                .padding(.horizontal, compactExtraInset)
                .animation(Self.widthSpring, value: isCompact)
            }
            content
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { composerRowHeight = $0 }
                .preference(key: BarAccessoriesKey.self, value: BarAccessories(restHeight: composerRowHeight))
        }
        .onChange(of: mentions == nil ? nil : composer.mentionQuery?.text, initial: true) { _, query in
            mentions?.update(query: query)
        }
        .onChange(of: mentions?.candidates ?? [], initial: true) { old, new in
            // An open list changing size is the glass changing shape, so the whole bar moves in one
            // transaction: the card, where the stack places it and where the host places the stack.
            // Animated any narrower — on the card alone — the outer placement snapped while the card's
            // size ramped, and the card's bottom lifted off the composer by a row and settled back.
            // Opening and closing stay unanimated; the clip's edge carries those.
            // Under an open reply strip, opening and closing are shape changes too: the list splits
            // out of the strip's glass and merges back into it.
            guard (!old.isEmpty && !new.isEmpty) || barReply != nil else {
                listedCandidates = new
                return
            }
            withAnimation(replySpring) { listedCandidates = new }
        }
        .onChange(of: composer.replyTarget, initial: true) { _, target in
            // Under an open list, the strip appearing and the list giving up a row are one shape
            // change. Apart, the list's card resized at once inside its animating frame and its top
            // edge snapped by a row before the spring moved it.
            guard mentionCandidates != nil else {
                listedReply = target
                return
            }
            withAnimation(target == nil ? ChatMotion.replyMerge.animation : replySpring) { listedReply = target }
        }
    }

    /// Whether a reply strip stands under the mention list.
    private var replyOpen: Bool { barReply != nil }

    /// The reply the strip and the list's row cap follow. With the list closed it is the
    /// composer's own, so the clip still uncovers the strip in the update that aims it.
    private var barReply: ComposerModel.ReplyTarget? {
        mentionCandidates == nil ? composer.replyTarget : listedReply
    }

    /// What the mention list shows, or `nil` while it is closed. Tied to the live query as well as
    /// the model, so a send or a pick closes it in the same update rather than after the search.
    private var mentionCandidates: [ConversationMember]? {
        guard mentions != nil, composer.mentionQuery != nil, !listedCandidates.isEmpty else { return nil }
        return listedCandidates
    }

    /// The tip CTA's title. Names the amount that opens the chat when a floor
    /// has resolved; the fee is what the recipient charges for the
    /// conversation, so stating it is the whole point of the button.
    private var startChattingTitle: String {
        guard let startChattingFee else { return "Start Chatting" }
        return "Send \(startChattingFee.formatted()) to Start Chatting"
    }
}

/// A card's arrival and departure above the composer row — the reply strip or the mention list:
/// what the bar's top edge uncovers on the way in and closes back over on the way out.
///
/// The travel itself is not here. The bar is hosted in a box that clips it, and that box's edge is
/// what moves — see `ChatScreenViewController`'s `barClip`. This view only decides *what* height the
/// bar has to be for the strip to fit, and it takes that height in one step: the strip is laid out
/// at full size the moment it mounts, behind the clip's edge, and stays there until the edge has
/// closed over it again. Two animators over one edge is what put the composer row 24pt off its mark.
///
/// Height-driven and clipped rather than a transition, because any transition that moves or fades
/// the quote on its own detaches it from the edge above it: `.move(edge: .bottom).combined(with:
/// .opacity)` slid the quote down behind the field and dissolved it there while the edge travelled
/// separately. Clipping welds them — the quote holds still against the field below it while the
/// edge uncovers it.
private struct AccessoryReveal<Item: Equatable, Card: View>: View {

    /// Which card this is, as the bar reports it to the clip.
    let kind: BarAccessories.Kind
    let target: Item?
    /// Whether this card opens and closes by changing its own height instead of under the clip's
    /// edge. The edge only ever moves at the top of the bar, so a card with another one open above
    /// it has to resize itself: closed by the edge, the card above was cut away instead.
    let collapsesInPlace: Bool
    @ViewBuilder let card: (Item) -> Card

    init(
        kind: BarAccessories.Kind,
        item: Item?,
        collapsesInPlace: Bool = false,
        @ViewBuilder card: @escaping (Item) -> Card
    ) {
        self.kind = kind
        self.target = item
        self.collapsesInPlace = collapsesInPlace
        self.card = card
    }

    /// The strip's own height. Measured rather than declared: a snippet that wraps to a second line
    /// makes the sheet taller, and the clip has to know by how much.
    ///
    /// Kept across replies. The strip mounts before it can be measured — on the first reply it comes
    /// up at zero height, reports what it wants, and only then takes it — and the bar's host reads
    /// that second step as the opening.
    @State private var naturalHeight: CGFloat = 0
    /// The last target seen, kept after the target clears. A strip that unmounts on the way out has
    /// nothing to draw while it collapses, and the sheet slides back under the field empty.
    @State private var retained: Item?
    /// The quote's own opacity, which only ever moves on the way out.
    ///
    /// Asymmetric on purpose. Coming in, the edge uncovering the quote is the whole effect and a
    /// fade would soften it; going out, a quote that stays fully opaque until the clip eats it reads
    /// as the text being sliced off, so it dissolves as the sheet closes. `replySurface` has no
    /// bounce, which is what makes it safe to drive opacity: a spring that overshoots clamps at 0
    /// and 1 and flickers.
    @State private var contentOpacity: CGFloat = 1
    /// Whether a list opening beside the strip has grown out of it yet. It mounts collapsed and grows
    /// on the next turn; mounted at full size, the container faded its glass in where it stood.
    @State private var grown = true

    /// What the strip draws: the live target while a reply is open, and the one it is closing over
    /// afterwards.
    ///
    /// Reading `target` first, rather than the retained copy alone, is what makes the sheet
    /// self-correcting — whether it is open is derived from the target on every update instead of
    /// being latched by a transition. A reply that arrives with no transition to catch opens like
    /// any other: a draft restored into the composer is aimed before the bar is on screen, and the
    /// gate keeps the bar unmounted until the chat's rules land, so the target can change while
    /// there is no `onChange` to fire and be in place before `onAppear` would set anything. Latched,
    /// a missed transition was also unrecoverable: `ReplyTarget` is `Equatable`, so aiming at the
    /// same message again is not a change and `onChange` never fires for it twice.
    ///
    /// Beside another open card there is no clip to close over, and the retained copy collapses its
    /// own glass down into the composer instead — see `collapsing`.
    private var shown: Item? { target ?? retained }

    /// Whether this card is closing beside another open one: its glass shrinks toward the composer
    /// while the card beside it grows into the room. Removed outright instead, the glass dissolved
    /// in place and the other card snapped to its new size.
    private var collapsing: Bool { collapsesInPlace && (target == nil || !grown) }

    /// Whether this is the strip closing beside the open list. It keeps its shape and fades out,
    /// glass and all, while the list grows down over the room it gives up. Shrunk into the composer
    /// instead, the strip's glass was squeezed into a sliver.
    private var fadingOut: Bool { kind == .reply && collapsing }

    /// Whether the card takes its own height instead of the measured one. Every change that isn't
    /// the clip's to reveal is drawn by the card resizing, so its glass changes shape and the rows
    /// inside keep their places. Held at the measured height, a list gaining a row as the strip
    /// left was drawn into the old frame and showed its last rows until the frame caught up.
    private var sizesItself: Bool {
        collapsesInPlace || (target != nil && kind == .mentions && naturalHeight > 0)
    }

    /// How much height the strip is asking the bar for. Zero until it has been measured, and held at
    /// full height right through the exit — the clip closes over the quote, so there has to be a
    /// quote there to close over.
    private var revealHeight: CGFloat {
        guard shown != nil, !(collapsesInPlace && target == nil) else { return 0 }
        return naturalHeight
    }

    var body: some View {
        Group {
            if let shown {
                card(shown)
                    // Faded inside the glass, not around it: a glass container draws its cards
                    // itself, and an opacity outside the card never reached the quote, which stayed
                    // drawn across the list's last row through the whole merge.
                    .environment(\.barCardContentOpacity, contentOpacity)
                    .environment(\.barCardCollapsed, collapsing && !fadingOut)
                    .environment(\.barCardFading, fadingOut)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { measured in
                        guard naturalHeight != measured else { return }
                        // Drawn in place, the frame below follows the card in one transaction for the
                        // whole bar, for the reason in `ConversationBottomBar`'s `onChange(of:
                        // candidates)`: the mention list resizing while open, or the reply strip opening
                        // under it. Anything else is the clip's to reveal and stays unanimated.
                        let inPlace = target != nil
                            && (collapsesInPlace || (kind == .mentions && naturalHeight > 0))
                        withAnimation(inPlace ? replySpring : nil) { naturalHeight = measured }
                    }
                    // Out of the layout but still drawn, hung above the composer, so the list's
                    // lower edge travels down over it as it fades. A measured height rather than
                    // nil while open, so the step to zero is one the spring can interpolate: from
                    // nil it snapped, and the list jumped down in a frame instead of growing.
                    .frame(height: fadingOut ? 0 : (naturalHeight > 0 ? naturalHeight : nil), alignment: .bottom)
            }
        }
        // The strip keeps its own height whatever the frame below proposes, so the frame can clip it
        // instead of squashing it.
        .fixedSize(horizontal: false, vertical: true)
        // Bottom-aligned, so the card's lower edge stays welded to the composer whatever this frame
        // does. The card and this frame resize on the same spring but a measurement apart, and with
        // the card hung from the top, any gap between the two showed as its bottom edge lifting off
        // the composer and settling back.
        .frame(height: sizesItself ? nil : revealHeight, alignment: .bottom)
        .clipShape(RevealClip(overhang: fadingOut ? naturalHeight : 0))
        // Opening and closing under the clip stay unanimated, and innermost so they win if another
        // change lands with them: there this height is the bar's *requirement*, not the motion, and
        // the clip around the bar travels it in UIKit. A card under the open mention list has no
        // clip edge to ride, so it draws its own open and close.
        .animation(collapsesInPlace ? replySpring : nil, value: shown == nil)
        .animation(collapsesInPlace ? replySpring : nil, value: target == nil)
        // `clipped()` is a drawing bound, not a hit-testing or accessibility one, so the collapsed
        // copy stays pressable and findable until the task below unmounts it.
        .allowsHitTesting(target != nil)
        .preference(key: BarAccessoriesKey.self, value: report)
        // Drop the retained copy once it has finished sliding back under the field. It has to
        // outlive the target — there is nothing to draw during the collapse otherwise — but only by
        // the length of the collapse: left mounted, it leaves a zero-height quote in the
        // accessibility tree that VoiceOver still reads and the UI tests still find. Hiding it
        // instead of unmounting it does not work; the strip's own `children: .contain` container
        // survives an ancestor's `accessibilityHidden`.
        //
        // Giving the height back is the same step, since `shown` goes with the retained copy:
        // any earlier and the bar would shrink out from under a clip that is still closing, and show
        // a band of the screen behind it above the composer.
        //
        // `.task(id:)` cancels on the next change, so replying again mid-collapse keeps its strip.
        .task(id: target) {
            guard target == nil, retained != nil else { return }
            // A strip fading beside the list stays until the list has settled over it: its glass,
            // joined to the list's, draws the bottom edge until it goes, and dropped at the spring's
            // perceptual length it left the list's own edge 3pt short, creeping down after the strip
            // was gone.
            let stay = fadingOut ? ChatMotion.replySurface.duration * 1.6 : ChatMotion.replySurface.duration
            try? await Task.sleep(for: .seconds(stay))
            retained = nil
            // Back to opaque with nothing mounted, so the next reply starts from a clean state
            // rather than fading in from wherever the last exit left it.
            contentOpacity = 1
        }
        .onChange(of: target) { oldValue, newValue in
            guard let newValue else {
                close()
                return
            }
            if oldValue == nil, collapsesInPlace, kind == .mentions {
                grown = false
                Task { @MainActor in
                    withAnimation(replySpring) { grown = true }
                }
            }
            // Only for the exit: `shown` already draws the live target. This is the copy the clip
            // closes over once the target is gone.
            retained = newValue
            // Only ever a correction: a reply started while the last one was still fading out. A
            // fresh reply already has this at 1, so nothing animates.
            withAnimation(ChatMotion.replySurface.animation) { contentOpacity = 1 }
        }
        // Same copy, for a bar that mounts with a reply already open.
        .onAppear { retained = target }
    }

    /// What this card tells the clip: open once it has a height to open by, and closing for as
    /// long as its retained copy is still mounted underneath.
    private var report: BarAccessories {
        var accessories = BarAccessories()
        if target != nil, naturalHeight > 0 {
            accessories.open = [kind]
        } else if target == nil, retained != nil, !collapsesInPlace {
            accessories.exitingHeight = naturalHeight
        }
        // Zero once it is collapsing beside the list: the room already has it back.
        if kind == .reply { accessories.restHeight = revealHeight }
        return accessories
    }

    /// The quote dissolves; its height stays. The clip is what closes over it, and it needs
    /// something to close over — the height goes back with the retained copy above.
    private func close() {
        // The list's rows sit in a scroll view, which escapes the card's clip while the card
        // collapses and drew the rows across the strip and the composer. Only its glass shrinks.
        if collapsesInPlace, kind == .mentions {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { contentOpacity = 0 }
            return
        }
        // The strip beside the open list leaves the glass container in the close's own animation,
        // which draws it flowing back into the list along a neck: the peel run in reverse.
        if collapsesInPlace, kind == .reply {
            withAnimation(ChatMotion.replyMerge.animation) { retained = nil }
            return
        }
        // Beside the list the quote goes well before its glass: the list grows over the strip as
        // it fades, and the quote's text showed through under the list's new row.
        withAnimation(fadingOut ? .easeOut(duration: 0.14) : ChatMotion.replySurface.animation) {
            contentOpacity = 0
        }
    }
}

/// The cards above the composer row, gathered for the bar's measurement.
extension EnvironmentValues {
    /// The namespace the bar's cards share their glass in, so one can split out of another.
    @Entry var barCardGlassNamespace: Namespace.ID? = nil
    /// How far a bar card's content has faded, applied beneath its glass.
    @Entry var barCardContentOpacity: CGFloat = 1
    /// Whether a bar card is closing into the composer beside another open card, its glass and its
    /// margins shrinking to nothing.
    @Entry var barCardCollapsed: Bool = false
    /// Whether a bar card is fading out whole, its glass included, beside another open card.
    @Entry var barCardFading: Bool = false
}

/// The reveal's clip, open above by `overhang` so a card fading out of the layout stays drawn.
nonisolated private struct RevealClip: Shape {
    var overhang: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - overhang, width: rect.width, height: rect.height + overhang))
    }
}

/// Where the bar's cards keep their glass: one container, so a card opening beside another peels
/// off its surface instead of fading in, and merges back into it on the way out.
///
/// The composer stays outside it. Its glass is a background behind an editable field, and a
/// container composites glass above sibling content.
private struct BarCardGlassContainer<Content: View>: View {
    @Namespace private var namespace
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: BarCardGlass.spacing) {
                VStack(spacing: 0) { content }
            }
            .environment(\.barCardGlassNamespace, namespace)
        } else {
            VStack(spacing: 0) { content }
        }
    }
}

/// A bar card's Liquid Glass, joined to the cards beside it when it has a container to share.
struct BarCardGlass: ViewModifier {

    /// How close two cards' glass has to come to flow together: the 12pt gap the cards rest at, so
    /// a splitting card stays joined by a bridge across its whole travel and pinches off as it
    /// settles. At 8pt the bridge broke in the first frames and the split read as a plain fade.
    static let spacing: CGFloat = 12

    let id: BarAccessories.Kind
    @Environment(\.barCardGlassNamespace) private var namespace
    @Environment(\.barCardContentOpacity) private var contentOpacity
    @Environment(\.barCardCollapsed) private var collapsed
    @Environment(\.barCardFading) private var fading

    /// How fast a card fading out beside another goes: the length of the reply spring, so the exit
    /// takes as long as the peel it reverses. At 0.2s it read as faster than the enter.
    private static let fade: Animation = .easeInOut(duration: ChatMotion.replySurface.duration)

    func body(content: Content) -> some View {
        if #available(iOS 26, *), let namespace {
            // Applied to the content, not as a background: a container draws background glass over
            // the content beside it.
            content
                .collapsingCard(collapsed)
                .opacity(contentOpacity)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: BarMetrics.cornerRadius))
                .glassEffectID(glassID, in: namespace)
                .glassEffectTransition(.matchedGeometry)
                .opacity(fading ? 0 : 1)
                .animation(Self.fade, value: fading)
        } else {
            content
                .collapsingCard(collapsed)
                .glassFieldBackground(cornerRadius: BarMetrics.cornerRadius)
                .opacity(fading ? 0 : contentOpacity)
                .animation(Self.fade, value: fading)
        }
    }

    /// A plain string, since `Kind`'s `Hashable` conformance is main-actor isolated and the glass
    /// wants a `Sendable` one.
    private var glassID: String {
        switch id {
        case .mentions: "mentions"
        case .reply: "reply"
        }
    }
}

private extension View {
    /// How fast a collapsing card's content goes, well inside the shape's spring.
    static var collapseFade: Animation { .easeOut(duration: 0.1) }

    /// Shrinks the card's shape to nothing against its lower edge, so the glass drawn around it
    /// sinks into the composer rather than being cut off by a frame outside it.
    ///
    /// The content keeps its own height and is clipped, not laid out into the shrinking frame:
    /// squeezed, the quote reflowed to one line and drew its author's name across it.
    func collapsingCard(_ collapsed: Bool) -> some View {
        fixedSize(horizontal: false, vertical: true)
            // Gone before the shape is: faded on the shape's spring, the quote and its close button
            // stayed drawn across the thinning sliver.
            .opacity(collapsed ? 0 : 1)
            .animation(Self.collapseFade, value: collapsed)
            .frame(height: collapsed ? 0 : nil, alignment: .bottom)
            .clipShape(RoundedRectangle(cornerRadius: BarMetrics.cornerRadius))
    }
}

struct BarAccessoriesKey: PreferenceKey {
    static let defaultValue = BarAccessories()
    static func reduce(value: inout BarAccessories, nextValue: () -> BarAccessories) {
        value = value.merged(with: nextValue())
    }
}

/// The glass type box: a multiline field with a confirm button — an arrow that appears once there's
/// text, a checkmark for the length of an edit. Swiping the chat down lowers the keyboard and the box.
struct ConversationComposer: View {

    let conversationID: ConversationID?
    @Bindable var model: ConversationBarModel
    @Bindable var composer: ComposerModel

    @Environment(ConversationController.self) private var conversationController
    @FocusState private var isFocused: Bool

    /// Send button scale-in/out as text appears/clears.
    private static let sendButtonSpring = ChatMotion.sendButton.animation

    var body: some View {
        let field = HStack(alignment: .bottom, spacing: 10) {
            TextField(fieldPrompt, text: $composer.draft, selection: $composer.selection, axis: .vertical)
                .font(.appTextMessage)
                .foregroundStyle(Color.textMain)
                .tint(.white)
                .lineLimit(1...5)
                .focused($isFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: BarMetrics.fieldMinHeight)
                // Queried by the UI tests. The placeholder is not usable as a handle: it is gone the
                // moment there is a draft, so a test that types and then reads the field back finds
                // nothing. A multiline `TextField(axis:)` also surfaces as a text view wearing a
                // text-field automation type, so the query has to be identifier-based, not type-based.
                .accessibilityIdentifier("composer-message-field")

            // The spring is scoped to the button, not to the row. On the row it took the field
            // into the transaction as well, and `showsSubmit` falls on the same update that empties
            // the draft — so the field's text update ran as an animated one against its text view,
            // where it can be coalesced away. That leaves the sent text on screen with the binding
            // already empty, and an unchanged binding never pushes it again.
            Group {
                if showsSubmit {
                    Button(action: submit) {
                        Image(systemName: submitSymbol)
                            .font(.default(size: 16, weight: .bold))
                            .foregroundStyle(Color.textAction)
                            .frame(width: 34, height: 34)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                            // Arrow and checkmark are the same button in two jobs, so the glyph swaps in
                            // place rather than the button popping out and a new one popping back.
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(composer.isEditing ? "Save" : "Send")
                    .accessibilityIdentifier("send-message-button")
                    // Pop from 60% + fade, so the opacity ramp actually reads
                    // (scaling from 0 hides the fade behind a tiny speck).
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(Self.sendButtonSpring, value: showsSubmit)
        }

        return field
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, BarMetrics.fieldVerticalPadding)
        // Glass *behind* the field, not wrapping it: wrapping an editable
        // TextField in `glassEffect` reparents its text view into the glass
        // platter and breaks the text-selection grabbers.
        .glassFieldBackground(cornerRadius: BarMetrics.cornerRadius)
        // Focus is the single source of `isComposing` — the button morph and the
        // screen's interactive-dismiss gate both key off it. Losing focus
        // (keyboard swiped down) ends composing.
        .onChange(of: isFocused) { _, focused in
            withAnimation(barMorphSpring) { model.isComposing = focused }
            if !focused, let conversationID {
                conversationController.stopSelfTyping(in: conversationID)
            }
        }
        .onChange(of: composer.draft) { _, text in
            guard let conversationID else { return }
            conversationController.draftDidChange(text, in: conversationID)
        }
    }

    /// The hint names what the field will send. An edit arrives with the existing text already in
    /// the field, so its hint is never on screen and stays the new-message one.
    private var fieldPrompt: String {
        switch composer.mode {
        case .new, .editing:    "Message"
        case .replying:         "Reply"
        }
    }

    /// The confirm button is up for the whole of an edit, as it is in WhatsApp, and only once
    /// there's text to send otherwise.
    private var showsSubmit: Bool { composer.isEditing || composer.canSubmit }

    private var submitSymbol: String {
        composer.isEditing ? SystemSymbol.checkmark.rawValue : SystemSymbol.arrowUp.rawValue
    }

    private func submit() {
        guard let conversationID else { return }

        // Fire-and-forget in both branches: the change applies optimistically and resolves on its own,
        // so the composer stays ready immediately. Emptying the field up front makes a double-tap a
        // no-op, because there is then nothing to submit.
        switch composer.mode {
        case .new:
            guard let text = composer.submission else { return }
            // Snapshotted before the field is emptied: a send that fails has no persisted record on
            // this platform, so this is the only copy of the words left to put back.
            let draft = composer.persistableDraft
            composer.clear()
            isFocused = true
            Task { await conversationController.send(text, to: conversationID, restoringOnFailure: draft) }
        case .replying(let target):
            guard let text = composer.submission else { return }
            // The strip travels with the text. Restoring the words alone would downgrade a reply to
            // a loose message, which is the wrong-context send this is here to prevent.
            let draft = composer.persistableDraft
            composer.clear()
            isFocused = true
            Task {
                await conversationController.send(
                    text,
                    to: conversationID,
                    repliedTo: target.messageID,
                    restoringOnFailure: draft
                )
            }
        case .editing(let messageID, _):
            // Confirming an edit that changed nothing leaves edit mode rather than round-tripping
            // the same text — the button is always there to be pressed.
            let text = composer.submission
            composer.endEditing()
            isFocused = true
            guard let text else { return }
            Task { await conversationController.edit(messageID: messageID, in: conversationID, to: text) }
        }
    }
}

/// The way out of an edit: the bar's leading control while the field holds an existing message,
/// standing where Send Cash stands the rest of the time. Field-sized and glass, so the swap reads
/// as the same control changing job rather than a foreign button arriving.
private struct CancelEditButton: View {

    let onCancel: () -> Void

    var body: some View {
        Button(action: onCancel) {
            Image(systemName: SystemSymbol.close.rawValue)
                .font(.default(size: 17, weight: .semibold))
                .foregroundStyle(Color.textMain)
                .frame(width: BarMetrics.contentHeight, height: BarMetrics.contentHeight)
                // The glyph is the only drawn content, so without a shape the taps that land on the
                // glass around it miss the button — the platter lights up (it is `.interactive`) and
                // the edit stays open. The shape makes the whole pill the target.
                .contentShape(RoundedRectangle(cornerRadius: BarMetrics.cornerRadius))
        }
        .buttonStyle(.plain)
        .glassBackground(cornerRadius: BarMetrics.cornerRadius)
        .clipShape(RoundedRectangle(cornerRadius: BarMetrics.cornerRadius))
        .accessibilityLabel("Cancel editing")
        .accessibilityIdentifier("cancel-edit-button")
    }
}

/// The Send Cash button, rendered as a white "Send €" pill at rest and a
/// compact glass "€" square while composing (or always, in a tip chat). Alone
/// in the bar it takes the standard filled-button size; beside the composer
/// it's field-sized.
// One persistent view: the morph animates its properties (prefix text, fill,
// width, color) in lockstep — splitting the two states into separate views
// would crossfade instead of morphing.
struct SendCashMorphButton: View {

    let symbol: String
    let composing: Bool
    /// Whether the button is the bar's only control (no chat yet): it spans
    /// the bar at the standard filled-button size instead of field-sized.
    let standalone: Bool
    /// Forces the compact symbol-only presentation regardless of composing.
    /// The bar sets it once a chat exists; only the pre-chat CTA expands.
    var alwaysMinimized: Bool = false
    /// Replaces "Send <symbol>" while expanded. A tip chat names the tip
    /// instead of the currency, because the amount is chosen on the next screen.
    var expandedTitle: String?
    let action: () -> Void

    /// The compact glass "€" presentation: while composing, or always once a
    /// chat exists. The whole morph (label, fill, width, color) keys off this.
    private var minimized: Bool { composing || alwaysMinimized }

    private var height: CGFloat {
        standalone ? Metrics.buttonHeight : BarMetrics.contentHeight
    }

    private var cornerRadius: CGFloat {
        standalone ? Metrics.buttonRadius : BarMetrics.cornerRadius
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !minimized {
                    Text(expandedTitle ?? "Send")
                        .font(.appTextMedium)
                        .transition(.opacity)
                }
                // Suppressed while a custom title is showing: "Send a Tip $"
                // isn't a label. It returns when the button minimizes.
                if minimized || expandedTitle == nil {
                    Text(symbol)
                        // Same persistent Text — .interpolate animates the glyph
                        // between sizes; swapping views would crossfade.
                        .font(minimized ? .appTextXL : .appTextMedium)
                        .contentTransition(.interpolate)
                }
            }
            .foregroundStyle(minimized ? Color.textMain : Color.textAction)
            // The label must never reflow to "Se…" mid-morph; overflow is
            // clipped by the shape instead.
            .fixedSize()
            .padding(.horizontal, minimized ? 0 : 20)
            .frame(minWidth: BarMetrics.contentHeight)
            .frame(maxWidth: standalone && !minimized ? .infinity : nil)
            .frame(height: height)
            // The label is the only drawn content and the fill is a background on the button, not
            // on the label, so with `.plain` only the text was the target: alone in the bar the
            // pill spans the width but "Send a Tip" answered a tap on its centre and nothing else.
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        // White fill above the glass base: fading it out is the white → glass
        // change, without ever swapping views.
        .background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.action)
                .opacity(minimized ? 0 : 1)
        }
        .glassBackground(cornerRadius: cornerRadius)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityLabel(expandedTitle ?? "Send Cash")
        .accessibilityIdentifier("send-cash-button")
    }
}

#Preview("Morph") {
    @Previewable @State var composing = false
    ZStack {
        Color.backgroundMain.ignoresSafeArea()
        VStack {
            Spacer()
            HStack(spacing: 10) {
                SendCashMorphButton(symbol: "€", composing: composing, standalone: false) {
                    withAnimation(barMorphSpring) { composing.toggle() }
                }
                RoundedRectangle(cornerRadius: BarMetrics.cornerRadius)
                    .fill(.white.opacity(0.1))
                    .frame(height: BarMetrics.contentHeight)
            }
            .padding(12)
        }
    }
}

#Preview("Standalone") {
    ZStack {
        Color.backgroundMain.ignoresSafeArea()
        VStack {
            Spacer()
            SendCashMorphButton(symbol: "€", composing: false, standalone: true) {}
                .padding(12)
        }
    }
}
