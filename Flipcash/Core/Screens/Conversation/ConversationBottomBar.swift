//
//  ConversationBottomBar.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import PhotosUI
import SwiftUI
import FlipcashCore
import FlipcashUI

/// Shared state for the unified bottom bar: the focus-driven `isComposing` flag that drives the
/// Send Cash morph and the screen's interactive-dismiss gate. The draft itself lives in
/// `ComposerModel`, which also knows whether it is a new message or an edit.
@MainActor @Observable final class ConversationBarModel {
    var isComposing = false
    /// The camera or photo card the attach panel expands into.
    let attachCard = AttachCard()
    /// The attach menu's floating panel, grown out of `+`.
    let attachPanel = AttachPanel()
    /// Gets the camera running ahead of the camera card.
    let attachWarmUp = AttachWarmUp()
    /// The photo card's pick, kept across Back so its picker is mounted once per panel.
    let photosPick = AttachPhotosPick()
    /// Whether the panel and cards are drawn over the keyboard instead of in the bar.
    let overKeyboard = AttachOverKeyboard()

    /// The card's top edge in window coordinates, as last laid out.
    var cardTop: CGFloat = 0

    /// What the attach surface is showing.
    var attachSurfacePhase: AttachSurfacePhase {
        AttachSurfacePhase(
            isMenuOpen: attachPanel.isOpen,
            card: attachCard.content,
            isLanding: attachCard.landingChipID != nil
        )
    }

    /// Whether the attach surface is on screen: from the panel opening until the last exit, a card's
    /// or a landing's, has run.
    var attachSurfaceIsMounted: Bool {
        attachPanel.holdsOverflow || attachCard.holdsOverflow || attachCard.landingChipID != nil
    }

    /// Whether the surface is drawn where `+` stands, as `+`: from the panel opening until it has
    /// collapsed back, except while it shrinks onto a chip and leaves `+` to show again.
    var surfaceStandsInForPlus: Bool {
        attachSurfaceIsMounted && attachSurfacePhase != .landing
    }

    /// What the screen has to give the bar above its own frame for the panel and the card.
    var overflow: BarOverflow {
        guard attachPanel.holdsOverflow || attachCard.holdsOverflow else { return .none }
        // A panel or card over the keyboard draws in the keyboard's window and takes its own
        // touches there.
        if overKeyboard.isActive { return .none }
        if attachPanel.isOpen { return .everywhere }
        // A leaving card takes no touches: the band closes to the bar's own frame.
        return .band(top: attachCard.isOpen ? cardTop : .greatestFiniteMagnitude)
    }

    /// Takes the camera or photo card back into the attach panel, discarding any pick: one
    /// transaction, so the surface springs from the card's frame to the menu's.
    func returnToMenu() {
        guard attachCard.isOpen else { return }
        photosPick.reset()
        withAnimation(ChatMotion.attachCard.animation, completionCriteria: .logicallyComplete) {
            attachCard.close()
            attachPanel.open()
        } completion: { [weak self] in
            self?.attachCard.exitDidFinish()
        }
    }

    /// Takes the panel and the card down at once, with nothing to animate out: the keyboard they were
    /// drawn over went, or the app left the foreground.
    func resetAttach() {
        attachPanel.dismiss()
        attachPanel.exitDidFinish()
        attachCard.close()
        attachCard.exitDidFinish()
        attachCard.endLanding()
        photosPick.reset()
    }

    /// The landing chip was laid out at `frame`, in window coordinates: the card shrinks onto it the
    /// first time, and follows it on the card's spring if it moves while the card is shrinking.
    func landingChipDidLayout(_ frame: CGRect) {
        let card = attachCard
        let wasPlaced = card.landingChipFrame != nil
        guard !wasPlaced else {
            withAnimation(ChatMotion.attachCard.animation) { _ = card.landingChipDidLayout(frame) }
            return
        }
        guard card.landingChipDidLayout(frame) else { return }
        card.animate({ card.close() }, then: { card.endLanding() })
    }
}

/// How the bar reaches above its own frame: not at all, everywhere for a panel that dismisses on any
/// outside touch, or from a window-space `top` down for a card that lets touches above it through to
/// the transcript.
enum BarOverflow: Equatable {
    case none
    case everywhere
    case band(top: CGFloat)

    /// Whether the bar draws above its own frame.
    var overflows: Bool {
        switch self {
        case .none:                 false
        case .everywhere, .band:    true
        }
    }

    /// Where, in window coordinates, the bar starts taking touches, or `nil` for everywhere it reaches.
    var touchTop: CGFloat? {
        switch self {
        case .none:                 .greatestFiniteMagnitude
        case .everywhere:           nil
        case .band(let top):        top
        }
    }
}

/// Hands the bar's ``BarOverflow`` to the screen hosting it whenever it changes.
struct BarOverflowReporting: ViewModifier {
    let model: ConversationBarModel
    let screen: () -> ChatScreenViewController?

    func body(content: Content) -> some View {
        content.onChange(of: model.overflow) { _, overflow in
            guard let screen = screen() else { return }
            // The band first, so the bar never overflows with the last one's touches.
            screen.barOverflowTouchTop = overflow.touchTop
            screen.barOverflowsTop = overflow.overflows
        }
    }
}

/// Single spring driving the bar's morphs: the focus-driven resize and the send-arrow pop.
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
    nonisolated static let fieldMinHeight: CGFloat = 34
    nonisolated static let fieldVerticalPadding: CGFloat = 8
    /// The field's padding on every side: where `+` stands in from the field's leading edge, and so
    /// how far the open attach menu reaches back past `+` to line up with the field.
    nonisolated static let fieldPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 14
    /// The composer field's corner, rounder than the bar's other controls.
    nonisolated static let fieldCornerRadius: CGFloat = fieldPadding + accessorySize / 2
    /// The height of every bar control: a single-line field plus its padding, and the height the
    /// Send Cash button morphs at while there is a composer beside it.
    nonisolated static let contentHeight: CGFloat = fieldMinHeight + fieldVerticalPadding * 2
    /// The diameter of the controls beside the text: `+`, the Send Cash button and the send button.
    nonisolated static let accessorySize: CGFloat = 34
    /// The bar's own margin around its controls, above and below.
    static let contentPadding: CGFloat = 8
    /// The margin between the bar's controls and the screen's sides while the keyboard is up.
    static let edgeInset: CGFloat = 12
    /// How far into the home indicator's safe area the compact bar rests while the keyboard is down.
    static let compactDrop: CGFloat = 8
    /// The margin between the compact bar's controls and the screen's sides.
    static let compactInset: CGFloat = 32
}

/// What stands outside the message field, beside it.
enum ConversationBarLeadingControl: Equatable {
    /// The way out of an edit.
    case cancelEdit
    /// The round `$` on the field's right, shown while the draft is empty.
    case cash
    /// Nothing beside the field.
    case none

    /// Returns the control for the bar's state. An edit wins; otherwise the round `$` when Send Cash
    /// is offered.
    init(isEditing: Bool, showsSendCash: Bool) {
        if isEditing {
            self = .cancelEdit
        } else if !showsSendCash {
            self = .none
        } else {
            self = .cash
        }
    }
}

/// What the field's row holds beside the send button: the `+` menu.
struct ConversationBarBottomRow: Equatable {
    /// The rows of the `+` menu; empty hides `+`. Never holds Cash, which the `$` beside the field
    /// takes over.
    let plusItems: [AttachMenuItem]

    /// A row with nothing in it.
    static let empty = ConversationBarBottomRow(plusItems: [])

    /// Whether there is nothing for `+` to open.
    var isEmpty: Bool { plusItems.isEmpty }

    /// Returns the row for the bar's state: empty during an edit; otherwise `+` while it has a row
    /// to open.
    init(isEditing: Bool, acceptsMedia: Bool, attachedCount: Int) {
        guard !isEditing else {
            self.init(plusItems: [])
            return
        }
        self.init(plusItems: AttachMenuItem.items(showsCash: false, acceptsMedia: acceptsMedia, attachedCount: attachedCount))
    }

    private init(plusItems: [AttachMenuItem]) {
        self.plusItems = plusItems
    }
}

/// The unified bottom bar: the attach menu beside the message field.
struct ConversationBottomBar: View {

    let showsSendCash: Bool
    let conversationID: ConversationID?
    let symbol: String
    let onSendCash: () -> Void
    let model: ConversationBarModel
    let composer: ComposerModel
    /// Whether the chat's participation rules leave this user anything to type. Anything but
    /// ``ConversationGatePresentation/open`` replaces the whole composer with the gate panel.
    var gate: ConversationGatePresentation = .open
    /// Display name of the mint the gate's requirement names, once resolved. See
    /// ``ConversationGatePanel``.
    var gateMintName: String? = nil
    /// How much more the gate's minimum asks the user to hold; see ``ConversationGatePanel/shortfall``.
    var gateShortfall: FiatAmount? = nil
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
    /// Whether the round `$` shows: while the draft is empty. Set in a transaction after the text
    /// update, so the split animates without carrying the field's text change with it.
    @State private var cashIsShown = true

    /// How far left of the field the row starts, for the attach menu to open out to. `$` stands to
    /// the field's right, so nothing does.
    private var menuLeadingReach: CGFloat { 0 }
    @Namespace private var composerGlassNamespace
    /// Whether the chat takes photos; false for an E2EE DM, whose encryption does not cover media.
    var acceptsMedia: Bool = false
    /// Fired as `+` opens the attach panel with the given rows: the panel goes up over the keyboard,
    /// or the keyboard goes down under it.
    var onAttachOpen: ([AttachMenuItem]) -> Void = { _ in }
    /// Opens the camera from the attach menu.
    var onCamera: () -> Void = {}
    /// Receives a photo the inline camera took.
    var onCameraCapture: (ChatCameraCapture) -> Void = { _ in }
    /// Fired by the camera card's back chevron.
    var onCameraCancel: () -> Void = {}
    /// Opens the photo card from the attach menu.
    var onPhotos: () -> Void = {}
    /// Receives the photos added from the photo card, in the order they were selected, with the
    /// loader already reading them.
    var onPhotosAdd: ([PhotosPickerItem], ChatPhotoPreloader<PhotosPickerItem>) -> Void = { _, _ in }
    /// Receives images dropped on the bar, such as the system screenshot thumbnail or an image
    /// from another app in split view. Only fired while the bar takes photos.
    var onImagesDropped: ([NSItemProvider]) -> Void = { _ in }
    /// Fired by the photo card's back chevron and escape gesture.
    var onPhotosBack: () -> Void = {}
    /// Where the reply strip's quoted photo loads its thumbnail from.
    var quoteThumbnailLocation: (ChatQuote.Kind) async -> ChatMediaLocation? = { _ in nil }

    /// The curve the bar narrows and widens on as the keyboard goes and comes.
    private static let widthSpring = Animation.spring(duration: 0.22, bounce: 0.14)
    /// `$` splitting from the field's glass and joining back into it. Low bounce, so the overshoot
    /// does not carry the drop back into the field it just left.
    private static let cashSpring = Animation.spring(duration: 0.42, bounce: 0.12)
    /// How long `$` waits for the send arrow to shrink out of the spot it buds from.
    private static let cashBudDelay: TimeInterval = 0.1
    /// `$`'s glyph between the field's trailing edge, where its glass buds, and its own place.
    private static let cashGlyphTravel = AnyTransition
        .offset(x: -(BarMetrics.contentHeight / 2 + leadingSpacing))
        .combined(with: .scale(scale: 0.4))
    /// The gap between the field and the control beside it: cancel-edit on its left, `$` on its right. The composer's glass joins across no
    /// more than this, so `$` stays bridged to the field while it travels and pinches off at rest.
    static let leadingSpacing: CGFloat = 10
    /// How close the composer's glass shapes come before they flow together: under the resting gap,
    /// so `$` is bridged to the field while it travels and stands clear of it at rest.
    private static let glassJoinDistance: CGFloat = 8

    /// Whether the bar sits inset from the screen's sides: at rest with the keyboard down. It widens
    /// to the full edge inset as the keyboard comes up.
    private var isCompact: Bool { !model.isComposing }

    /// How much further in than ``BarMetrics/edgeInset`` the controls and the reply quote sit.
    private var compactExtraInset: CGFloat { isCompact ? BarMetrics.compactInset - BarMetrics.edgeInset : 0 }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                shortfall: gateShortfall,
                onAddFunds: onGateAddFunds,
                onJoin: onGateJoin,
                isJoining: isJoiningChat
            )

        case .open:
            composerBar
        }
    }

    /// The glass behind the field and the controls beside it, drawn as one layer apart from them so
    /// `$` splits from the field and joins back into it. The real controls sit above it, outside the
    /// container: in one, the glass composites above sibling content and covers the typed text.
    @ViewBuilder
    private var composerGlass: some View {
        let field = RoundedRectangle(cornerRadius: BarMetrics.fieldCornerRadius, style: .continuous)
        // No stack spacing: it is added per gap even where the item between is zero-wide, and a
        // negative padding on that item is clamped to zero, so the field's glass came up short of
        // the field by the spacing.
        let layout = HStack(alignment: .bottom, spacing: 0) {
            switch leadingControl {
            case .cancelEdit:
                // The button's size, so the field's glass starts where the field does.
                Color.clear
                    .frame(width: BarMetrics.contentHeight, height: BarMetrics.contentHeight)
                    .padding(.trailing, Self.leadingSpacing)
            case .cash, .none:
                EmptyView()
            }
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .composerGlass(in: field, id: "field", namespace: composerGlassNamespace)
            if leadingControl == .cash {
                // Kept mounted and tucked into the field's trailing end while hidden. Removed, it
                // stood past the join distance and dissolved in place under the widening field.
                let side = BarMetrics.contentHeight
                let tucked = side * 0.4
                Color.clear
                    .frame(width: cashIsShown ? side : 0, height: side)
                    .padding(.leading, cashIsShown ? Self.leadingSpacing : 0)
                    .overlay(alignment: .trailing) {
                        Color.clear
                            .frame(width: cashIsShown ? side : tucked, height: cashIsShown ? side : tucked)
                            .composerGlass(in: Circle(), id: "cash", namespace: composerGlassNamespace)
                            // Centred in the field's rounded end, clear of its edge.
                            .padding(.trailing, cashIsShown ? 0 : (side - tucked) / 2)
                    }
            }
        }
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: Self.glassJoinDistance) { layout }
        } else {
            layout
        }
    }

    private var composerBar: some View {
        // Bottom-aligned, against the bar's own pinned bottom: the field is the side that grows, and
        // top-aligning the control beside it made the control travel with every line the draft
        // gained or lost. Nothing animates that travel — the bar's springs key on `isEditing`,
        // which doesn't move during a send — so it snapped while the bar's height
        // sprang underneath it.
        let motion = AttachMotion(reduceMotion: reduceMotion)
        let content = VStack(alignment: .leading, spacing: Self.rowSpacing) {
            HStack(alignment: .bottom, spacing: Self.leadingSpacing) {
                // An edit takes over the bar: the leading control becomes the way out of it and the
                // field's bottom row steps aside until it resolves, the way WhatsApp hides its accessory controls.
                switch leadingControl {
                case .cancelEdit:
                    CancelEditButton { composer.endEditing() }
                case .cash, .none:
                    EmptyView()
                }
                ConversationComposer(
                    conversationID: conversationID,
                    model: model,
                    composer: composer,
                    bottomRow: bottomRow,
                    hidesPlus: showsCard,
                    // Swapped out in one frame for the surface, which is drawn as `+` where it stands.
                    plusIsStoodInFor: model.surfaceStandsInForPlus && motion.animatesGeometry,
                    onAttachOpen: onAttachOpen,
                    sendWaitsForCashJoin: leadingControl == .cash
                )
                // Over the row's other controls, which the attach panel floats across.
                .zIndex(1)
                if leadingControl == .cash, cashIsShown {
                    ComposerCashButton(symbol: symbol, action: onSendCash)
                        // Rides the glass out of the field's trailing end and back into it, never
                        // seen inside the field: it shows once the bud is out and goes as it leaves.
                        .transition(.asymmetric(
                            insertion: Self.cashGlyphTravel
                                .combined(with: .opacity.animation(.easeIn(duration: 0.12).delay(Self.cashBudDelay + 0.06))),
                            removal: Self.cashGlyphTravel
                                .combined(with: .opacity.animation(.easeOut(duration: 0.1)))
                        ))
                }
            }
            .background {
                composerGlass
            }
            // A draft already there when the chat opens hides `$` without animating it out.
            .onAppear { cashIsShown = composer.draft.isEmpty }
            .onChange(of: composer.draft.isEmpty) { _, isEmpty in
                guard cashIsShown != isEmpty else { return }
                withAnimation(isEmpty ? Self.cashSpring.delay(Self.cashBudDelay) : Self.cashSpring) {
                    cashIsShown = isEmpty
                }
            }
            .onChange(of: menuLeadingReach, initial: true) { _, reach in
                model.overKeyboard.menuLeadingReach = reach
            }
            // Kept mounted under the card, so `+` is there for the surface to shrink back into and the
            // field is there to take focus the moment the card closes. Left visible, not faded: the
            // card grows over it and shrinks back onto it, so it is never seen missing. An open panel lets a touch on the row —
            // send included — fall through to the dismiss area behind the bar, so it only closes the panel.
            .allowsHitTesting(!showsCard && !model.attachPanel.isOpen)
            .accessibilityHidden(showsCard)
            // After the row's own opacity, so the surface does not fade with it.
            .overlay(alignment: .topLeading) {
                if model.attachSurfaceIsMounted, !model.overKeyboard.isActive, !bottomRow.plusItems.isEmpty {
                    attachSurface(items: bottomRow.plusItems)
                }
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
        // The whole bar, margins included, takes a dropped image. Images only: the field's own
        // text drop keeps plain text, and declines an image session, so it falls to this.
        .contentShape(Rectangle())
        .onDrop(of: [.image], delegate: ComposerImageDropDelegate(
            acceptsDrop: acceptsMedia && !composer.isEditing,
            onDrop: onImagesDropped
        ))
        .animation(barMorphSpring, value: composer.isEditing)
        // The strip arriving with its first chip and leaving with its last, on the chip spring unless
        // a capture's animation is already carrying it.
        .transaction(value: ComposerChipStrip.isShown(chipCount: composer.chips.count, isEditing: composer.isEditing)) { transaction in
            if transaction.animation == nil, !transaction.disablesAnimations {
                transaction.animation = ChatMotion.composerChip.animation
            }
        }
        .onChange(of: wantsCameraWarm) { _, wanted in
            model.attachWarmUp.update(wanted: wanted)
        }
        // A panel closed without a choice leaves no pick behind for the next one.
        .onChange(of: model.attachSurfaceIsMounted) { _, isMounted in
            if !isMounted {
                model.photosPick.reset()
            }
        }
        .onDisappear {
            model.attachWarmUp.update(wanted: false)
        }
        // Typing takes the attach panel down, as a tap outside it does.
        .onChange(of: composer.draft) {
            guard model.attachPanel.isOpen else { return }
            model.attachPanel.animate { $0.dismiss() }
        }
        // An edit takes `+`'s slot, and the panel or card with it, so Back has no panel to return to.
        .onChange(of: composer.isEditing) { _, isEditing in
            guard isEditing else { return }
            if model.attachCard.isOpen {
                model.attachCard.close()
                model.attachCard.exitDidFinish()
            }
            if model.attachPanel.isOpen {
                model.attachPanel.animate { $0.dismiss() }
            }
        }
        // So does focusing the field, whose send-button end the panel leaves uncovered.
        .onChange(of: model.isComposing) { _, isComposing in
            guard isComposing, model.attachPanel.isOpen else { return }
            model.attachPanel.animate { $0.dismiss() }
        }

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
                ComposerReplyStrip(target: target, thumbnailLocation: quoteThumbnailLocation) { composer.endReplying() }
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

    /// The gap between the bar's rows.
    private static let rowSpacing: CGFloat = 8

    /// Whether the camera or photo card is up over the composer row.
    private var showsCard: Bool {
        model.attachCard.isOpen
    }

    /// The attach surface in the bar: the menu standing on `+`, and the card standing on the composer
    /// row's bottom edge, a fixed share of the screen tall and as wide as the bar's controls are with
    /// the keyboard up. An overlay, so the bar's measured height — and with it the transcript's inset
    /// — stays the composer's.
    private func attachSurface(items: [AttachMenuItem]) -> some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let toRow: (CGRect) -> CGRect = { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
            AttachSurface(
                model: model,
                items: items,
                plus: toRow(model.overKeyboard.plusFrame),
                card: AttachSurfaceLayout.barCardRect(row: proxy.size, outset: compactExtraInset, height: model.attachCard.height),
                landing: model.attachCard.landingChipFrame.map(toRow),
                menuPlacement: .standsOnPlus,
                selectionLimit: AttachMenuItem.photosSelectionLimit(attachedCount: composer.chips.count),
                actions: AttachOverlayActions(
                    onCash: onSendCash,
                    onCamera: onCamera,
                    onPhotos: onPhotos,
                    onCameraCapture: onCameraCapture,
                    onCameraCancel: onCameraCancel,
                    onPhotosAdd: onPhotosAdd,
                    onPhotosBack: onPhotosBack
                ),
                opensLibraryOnAppear: model.overKeyboard.opensLibraryInBar
            ) { region, rect in
                if region == .card, let rect {
                    model.cardTop = rect.minY + origin.y
                }
            }
            .onAppear {
                // A turn later, so the card has read it first.
                DispatchQueue.main.async { model.overKeyboard.opensLibraryInBar = false }
            }
        }
    }

    /// Whether the camera should be warm: while the open panel offers it, or its card shows it.
    private var wantsCameraWarm: Bool {
        let showsCamera = model.attachCard.content == .camera
        return showsCamera || (model.attachPanel.isOpen && bottomRow.plusItems.contains(.camera))
    }

    private var leadingControl: ConversationBarLeadingControl {
        ConversationBarLeadingControl(
            isEditing: composer.isEditing,
            showsSendCash: showsSendCash
        )
    }

    private var bottomRow: ConversationBarBottomRow {
        ConversationBarBottomRow(
            isEditing: composer.isEditing,
            acceptsMedia: acceptsMedia,
            attachedCount: composer.chips.count
        )
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
    /// What the row holds beside the text: `+`.
    var bottomRow = ConversationBarBottomRow.empty
    /// Whether `+` is hidden under the camera or photo card.
    var hidesPlus = false
    /// Whether the attach surface is drawn in `+`'s place, which hides `+`.
    var plusIsStoodInFor = false
    /// Fired as `+` opens the attach panel with the given rows.
    var onAttachOpen: ([AttachMenuItem]) -> Void = { _ in }
    /// Whether `$` stands beside the field and merges into it as the draft starts, so the send
    /// arrow waits for it to land instead of appearing over it.
    var sendWaitsForCashJoin = false

    @Environment(ConversationController.self) private var conversationController
    @FocusState private var isFocused: Bool

    /// Send button scale-in/out as text appears/clears.
    private static let sendButtonSpring = ChatMotion.sendButton.animation
    /// How long the send arrow waits for `$` to merge into the field's trailing end.
    private static let cashJoinDelay: TimeInterval = 0.16
    /// The text's and chips' inset from the field's leading edge.
    private static let leadingInset: CGFloat = 14
    /// The stacked text's insets from the field's leading and trailing edges.
    private static let stackedHorizontalInset: CGFloat = 14
    /// The stacked text's inset from the field's top edge.
    private static let stackedTopInset: CGFloat = 16
    /// The gap between the row's controls and the text.
    private static let controlSpacing: CGFloat = 8
    /// The move between the one-row and stacked layouts.
    /// The clip around the bar follows a shrink on `replySurface`, so the glass shares it.
    private static let stackSpring = ChatMotion.replySurface.animation

    /// Whether the text spans the field with the controls in a row under it.
    @State private var isStacked = false
    /// The text's own layout, switched without animation: an animated width re-lays the text
    /// every frame, and UIKit chases each new caret position on its own timing.
    @State private var textIsStacked = false
    /// The text's offset from its new place, sprung back to zero so it travels as one piece.
    @State private var textShift: CGFloat = 0
    /// Whether send is up; follows `showsSubmit` in its own transaction so the pop animates.
    @State private var submitIsShown = false
    /// The text field's width while it sits inline between the controls.
    /// The row's width, which stacking does not change, so the inline text width can be derived
    /// in either layout rather than measured from a field that is about to move.
    @State private var rowWidth: CGFloat = 0
    /// The draft's width laid out on one line.
    @State private var draftLineWidth: CGFloat = 0

    private var hasPlus: Bool { !bottomRow.plusItems.isEmpty }

    private var inlineLeadingPadding: CGFloat {
        hasPlus ? BarMetrics.accessorySize + Self.controlSpacing : Self.leadingInset - BarMetrics.fieldPadding
    }

    private func textLeadingPadding(stacked: Bool) -> CGFloat {
        stacked ? Self.stackedHorizontalInset - BarMetrics.fieldPadding : inlineLeadingPadding
    }

    private var inlineTrailingPadding: CGFloat { BarMetrics.accessorySize + Self.controlSpacing }

    /// Stacks once the draft wraps or takes a newline, and unstacks only when it is cleared, so
    /// deleting back under one line does not bounce the layout.
    private func updateStacking() {
        let stacked = Self.stacks(
            draft: composer.draft,
            wasStacked: textIsStacked,
            draftLineWidth: draftLineWidth,
            inlineWidth: rowWidth > 0 ? rowWidth - inlineLeadingPadding - inlineTrailingPadding : 0
        )
        // Its own transaction, after the text update has landed: the whole bar follows the field up
        // or down, while the text update itself stays unanimated.
        guard stacked != textIsStacked else { return }
        let shift = textLeadingPadding(stacked: textIsStacked) - textLeadingPadding(stacked: stacked)
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            textIsStacked = stacked
            textShift = shift
        }
        // A frame later, so the shift has rendered before it springs back with the bar.
        Task { @MainActor in
            withAnimation(Self.stackSpring) {
                isStacked = stacked
                textShift = 0
            }
        }
    }

    /// Whether the composer stacks for `draft`, given whether it was stacked and the draft's
    /// one-line width against the inline field's.
    nonisolated static func stacks(draft: String, wasStacked: Bool, draftLineWidth: CGFloat, inlineWidth: CGFloat) -> Bool {
        guard !draft.isEmpty else { return false }
        if wasStacked || draft.contains(where: \.isNewline) { return true }
        return inlineWidth > 0 && draftLineWidth > inlineWidth
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let motion = AttachMotion(reduceMotion: reduceMotion)
        let textField = TextField(fieldPrompt, text: $composer.draft, selection: $composer.selection, axis: .vertical)
            .font(.appTextMessage)
            .foregroundStyle(Color.textMain)
            .tint(.white)
            .lineLimit(1...7)
            .focused($isFocused)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: BarMetrics.fieldMinHeight)
            // The multiline field's text view draws past its frame, so scrolled text would show
            // through the row's padding. Clipping here makes the frame the scroll viewport.
            .clipped()
            // Queried by the UI tests. The placeholder is not usable as a handle: it is gone the
            // moment there is a draft, so a test that types and then reads the field back finds
            // nothing. A multiline `TextField(axis:)` also surfaces as a text view wearing a
            // text-field automation type, so the query has to be identifier-based, not type-based.
            .accessibilityIdentifier("composer-message-field")

        // One row: `+`, the text, `$` until there is a draft, and send. Once the text wraps or takes
        // a newline the row stacks: the text spans the field and the controls drop to a row under
        // it, until the draft is cleared. The text field never moves in the hierarchy, only its
        // insets do, so it keeps focus and the keyboard through the change.
        let controls = HStack(alignment: .bottom, spacing: 0) {
            if hasPlus {
                AttachMenu(
                    items: bottomRow.plusItems,
                    panel: model.attachPanel,
                    hidesButton: hidesPlus,
                    isStoodInFor: plusIsStoodInFor,
                    onOpen: onAttachOpen,
                    onPlusFrame: { model.overKeyboard.plusFrame = $0 }
                )
            }
            Spacer(minLength: 0)
            // The open menu covers this row; only `+` stays, for the menu to collapse back into.
            sendButton
                .animation(Self.sendButtonSpring) {
                    $0.opacity(model.attachPanel.isOpen ? 0 : 1)
                }
        }

        let row = ZStack(alignment: .bottomLeading) {
            textField
                .background(alignment: .leading) {
                    // The draft's width on one line, to tell when the inline field would wrap.
                    Text(composer.draft.isEmpty ? " " : composer.draft)
                        .font(.appTextMessage)
                        .lineLimit(1)
                        .fixedSize()
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                            draftLineWidth = width
                            updateStacking()
                        }
                }
                // The text snaps to its new layout and `textShift` carries it there on the bar's spring.
                .padding(.leading, textLeadingPadding(stacked: textIsStacked))
                .padding(.trailing, textIsStacked ? Self.stackedHorizontalInset - BarMetrics.fieldPadding : inlineTrailingPadding)
                .offset(x: textShift)
                // Position only, so it can spring with the bar without re-laying the text.
                // Chips above stand in for the top inset.
                .padding(.top, isStacked && composer.chips.isEmpty ? Self.stackedTopInset - BarMetrics.fieldPadding : 0)
                .padding(.bottom, isStacked ? BarMetrics.accessorySize + BarMetrics.fieldVerticalPadding : 0)
            controls
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            rowWidth = width
            updateStacking()
        }
        .onChange(of: composer.draft) { updateStacking() }
        // An empty field is small beside the space send will take; a tap anywhere right of `+`,
        // out to the field's edges, focuses it. Behind the row, so `+` keeps its own taps.
        .background {
            if composer.draft.isEmpty {
                Color.clear
                    .padding(.vertical, -BarMetrics.fieldPadding)
                    .padding(.trailing, -BarMetrics.fieldPadding)
                    .contentShape(Rectangle())
                    .onTapGesture { isFocused = true }
            }
        }

        // The staged photos ride inside the field, above the row, so the field reads as one message.
        let content = VStack(alignment: .leading, spacing: BarMetrics.fieldVerticalPadding) {
            if ComposerChipStrip.isShown(chipCount: composer.chips.count, isEditing: composer.isEditing) {
                ComposerChipStrip(
                    chips: composer.chips,
                    landingChipID: model.attachCard.landingChipID,
                    onLandingChipFrame: { model.landingChipDidLayout($0) },
                    onRemove: { composer.removeChip($0) },
                    onRetry: { $0.retryUpload() },
                    edgeInset: Self.leadingInset
                )
                // Out to the field's own edges, so chips scroll under a fade rather than a hard margin.
                .padding(.leading, -BarMetrics.fieldPadding)
                .padding(.trailing, -BarMetrics.fieldPadding)
                .padding(.top, BarMetrics.fieldVerticalPadding / 2)
                .transition(motion.stripTransition(isLanding: model.attachCard.landingChipID != nil))
            }
            row
        }

        return content
        .padding(BarMetrics.fieldPadding)
        // The field's glass is drawn by the bar, behind the whole row, so `$` can split from it.
        .composerRim(in: RoundedRectangle(cornerRadius: BarMetrics.fieldCornerRadius, style: .continuous))
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

    /// The confirm button. The spring is scoped to it, not to the row it sits in.
    private var sendButton: some View {
        // The spring is scoped to the button, not to the row. On the row it took the field
        // into the transaction as well, and `showsSubmit` falls on the same update that empties
        // the draft — so the field's text update ran as an animated one against its text view,
        // where it can be coalesced away. That leaves the sent text on screen with the binding
        // already empty, and an unchanged binding never pushes it again.
        // A ZStack, not a Group: a Group hands its modifiers to its children, so with the button
        // gone the slot's frame and the callbacks below would attach to nothing.
        ZStack {
            if submitIsShown {
                Button(action: submit) {
                    Image(systemName: submitSymbol)
                        .font(.default(size: 16, weight: .bold))
                        .foregroundStyle(Color.textAction)
                        .frame(width: BarMetrics.accessorySize, height: BarMetrics.accessorySize)
                        .background(Color.white, in: Circle())
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
        // The slot stays, so the text does not reflow as the button comes and goes.
        .frame(width: BarMetrics.accessorySize, height: BarMetrics.accessorySize)
        // Its own transaction after the text update: an implicit animation keyed on `showsSubmit`
        // rode the text field's update, which carries no animation, so the pop never played.
        .onAppear { submitIsShown = showsSubmit }
        .onChange(of: showsSubmit) { _, shows in
            let waits = shows && sendWaitsForCashJoin && !composer.isEditing
            withAnimation(waits ? Self.sendButtonSpring.delay(Self.cashJoinDelay) : Self.sendButtonSpring) {
                submitIsShown = shows
            }
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
        // A photo-only send leaves the draft as it was, so the draft's own dismissal never fires.
        if model.attachPanel.isOpen {
            model.attachPanel.animate { $0.dismiss() }
        }

        // Fire-and-forget in both branches: the change applies optimistically and resolves on its own,
        // so the composer stays ready immediately. Emptying the field up front makes a double-tap a
        // no-op, because there is then nothing to submit.
        switch composer.mode {
        case .new, .replying:
            guard let outgoing = composer.outgoing else { return }
            let repliedTo = composer.replyTarget?.messageID
            // Snapshotted before the field is emptied: a send that fails has no persisted record on
            // this platform, so this is the only copy of the words left to put back. A reply's strip
            // travels with the text, since restoring the words alone would downgrade it to a loose
            // message.
            let draft = composer.persistableDraft
            composer.clear()
            isFocused = true
            switch outgoing {
            case .text(let text):
                Task {
                    await conversationController.send(
                        text,
                        to: conversationID,
                        repliedTo: repliedTo,
                        restoringOnFailure: draft
                    )
                }
            case .media(let chips, let caption):
                // A photo that fails stays in the transcript to be retried, so nothing goes back
                // into the field.
                Task {
                    await conversationController.sendMedia(chips, caption: caption, to: conversationID, repliedTo: repliedTo)
                }
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
/// The round `$` beside the field. Its glass is drawn by the bar, joined to the field's.
private struct ComposerCashButton: View {

    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.appTextXL)
                .foregroundStyle(Color.textMain)
                .frame(width: BarMetrics.contentHeight, height: BarMetrics.contentHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .composerRim(in: Circle())
        .accessibilityLabel("Send Cash")
        .accessibilityIdentifier("send-cash-button")
    }
}

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


/// Takes images dropped on the composer. A chat that does not take photos refuses the drop with a
/// forbidden proposal, so the system shows it as refused instead of letting it land silently.
struct ComposerImageDropDelegate: DropDelegate {
    let acceptsDrop: Bool
    let onDrop: ([NSItemProvider]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.image])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: acceptsDrop ? .copy : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard acceptsDrop else { return false }
        let providers = info.itemProviders(for: [.image])
        guard !providers.isEmpty else { return false }
        onDrop(providers)
        return true
    }
}
