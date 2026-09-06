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

/// The curve the bar grows and shrinks on around the reply strip, and the one the surface changes
/// colour on. The slab itself is permanent, so nothing mounts or unmounts over the transcript.
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
    /// Tip chats always show the compact symbol-only send button; ordinary
    /// chats expand to "Send €" at rest and collapse only while composing.
    var isTipDm: Bool = false

    var body: some View {
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
                    // A tip chat sits minimized beside its composer, but before
                    // the first tip there is no composer to sit beside: the
                    // design draws the full-width "Send a Tip" (node 9443:8928).
                    alwaysMinimized: isTipDm && chatExists,
                    expandedTitle: isTipDm ? "Send a Tip" : nil,
                    action: onSendCash
                )
            }
            if chatExists {
                ConversationComposer(conversationID: conversationID, model: model, composer: composer)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
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
            // No `withAnimation` at the dismiss site either: the `.animation(_, value:)` below
            // already drives this state in both directions, and wrapping the dismissal in a second
            // transaction gave the exit a curve the entry never had.
            ComposerReplyReveal(target: composer.replyTarget) { composer.endReplying() }
            // On the composer row alone, not on the stack. The surface's job is to dissolve the
            // transcript into the input; anchoring it to the stack moved the dissolve up to the reply
            // strip's top edge, so a reply slid the fade 50pt up the screen and put an opaque slab
            // behind the quote. The quote is meant to sit over the transcript, not over the slab.
            content.modifier(BarSurfaceBackground())
        }
        .animation(replySpring, value: composer.replyTarget)
    }
}

/// The reply strip's arrival and departure: the quote the bar's top edge uncovers on the way in and
/// closes back over on the way out.
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
private struct ComposerReplyReveal: View {

    let target: ComposerModel.ReplyTarget?
    let onDismiss: () -> Void

    /// The strip's own height. Measured rather than declared: a snippet that wraps to a second line
    /// makes the sheet taller, and the clip has to know by how much.
    @State private var naturalHeight: CGFloat = 0
    /// Whether the strip is standing at its full height, 0 or 1 — never anything between.
    ///
    /// Kept as a factor of `naturalHeight` rather than a height switched on `target` because the
    /// strip has to mount before it can be measured: on a first reply it comes up at zero height,
    /// reports what it wants, and only then takes it. The bar's host reads that second step as the
    /// opening, so nothing depends on the two landing in one transaction.
    @State private var progress: CGFloat = 0
    /// The last target seen, kept after the target clears. A strip that unmounts on the way out has
    /// nothing to draw while it collapses, and the sheet slides back under the field empty.
    @State private var retained: ComposerModel.ReplyTarget?
    /// The quote's own opacity, which only ever moves on the way out.
    ///
    /// Asymmetric on purpose. Coming in, the edge uncovering the quote is the whole effect and a
    /// fade would soften it; going out, a quote that stays fully opaque until the clip eats it reads
    /// as the text being sliced off, so it dissolves as the sheet closes. `replySurface` has no
    /// bounce, which is what makes it safe to drive opacity: a spring that overshoots clamps at 0
    /// and 1 and flickers.
    @State private var contentOpacity: CGFloat = 1

    /// How much height the strip is asking the bar for. Zero until it has been measured, and held at
    /// full height right through the exit — the clip closes over the quote, so there has to be a
    /// quote there to close over.
    private var revealHeight: CGFloat { naturalHeight * progress }

    var body: some View {
        Group {
            if let retained {
                ComposerReplyStrip(target: retained, onDismiss: onDismiss)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { measured in
                        measure(measured)
                    }
            }
        }
        // The strip keeps its own height whatever the frame below proposes, so the frame can clip it
        // instead of squashing it.
        .fixedSize(horizontal: false, vertical: true)
        .frame(height: revealHeight, alignment: .top)
        .clipped()
        // Deliberately unanimated, and inside the bar's own `.animation(replySpring,
        // value: replyTarget)` so it wins: this height is the bar's *requirement*, not the motion.
        // The clip around the bar travels it, on that same spring, in UIKit.
        .animation(nil, value: revealHeight)
        .opacity(contentOpacity)
        // `clipped()` is a drawing bound, not a hit-testing or accessibility one, so the collapsed
        // copy stays pressable and findable until the task below unmounts it.
        .allowsHitTesting(target != nil)
        // Drop the retained copy once it has finished sliding back under the field. It has to
        // outlive the target — there is nothing to draw during the collapse otherwise — but only by
        // the length of the collapse: left mounted, it leaves a zero-height quote in the
        // accessibility tree that VoiceOver still reads and the UI tests still find. Hiding it
        // instead of unmounting it does not work; the strip's own `children: .contain` container
        // survives an ancestor's `accessibilityHidden`.
        //
        // `.task(id:)` cancels on the next change, so replying again mid-collapse keeps its strip.
        .task(id: target) {
            guard target == nil, retained != nil else { return }
            try? await Task.sleep(for: .seconds(ChatMotion.replySurface.duration))
            retained = nil
            // Only now does the bar stop needing the strip's height. Giving it back any earlier
            // would shrink the bar out from under a clip that is still closing, and show a band of
            // the screen behind it above the composer.
            progress = 0
            // Back to opaque with nothing mounted, so the next reply starts from a clean state
            // rather than fading in from wherever the last exit left it.
            contentOpacity = 1
        }
        .onChange(of: target) { _, newValue in
            guard let newValue else {
                close()
                return
            }
            retained = newValue
            // Open from here only when a previous reply already measured the strip. On the first one
            // the height is still unknown, and `measure(_:)` opens as soon as it arrives.
            if naturalHeight > 0 { open() }
        }
        .onAppear {
            retained = target
            // Already replying when the bar appears — there is no arrival to animate.
            progress = target == nil ? 0 : 1
            contentOpacity = 1
        }
    }

    /// Take the strip's measured height, and open the sheet if it was waiting on this measurement.
    ///
    /// A height that changes while the sheet is open is a real change — a one-line snippet replaced
    /// by a two-line one — so it moves the top edge on the same curve rather than stepping it.
    private func measure(_ measured: CGFloat) {
        guard naturalHeight != measured else { return }
        let wasUnmeasured = naturalHeight == 0
        naturalHeight = measured
        if wasUnmeasured, target != nil { open() }
    }

    private func open() {
        progress = 1
        // Only ever a correction: a reply started while the last one was still fading out. A fresh
        // reply already has this at 1, so nothing animates.
        withAnimation(ChatMotion.replySurface.animation) { contentOpacity = 1 }
    }

    /// The quote dissolves; its height stays. The clip is what closes over it, and it needs
    /// something to close over — `progress` goes back to zero once that has finished.
    private func close() {
        withAnimation(ChatMotion.replySurface.animation) { contentOpacity = 0 }
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
            TextField("Message", text: $composer.draft, axis: .vertical)
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
            composer.clear()
            isFocused = true
            Task { await conversationController.send(text, to: conversationID) }
        case .replying(let target):
            guard let text = composer.submission else { return }
            composer.clear()
            isFocused = true
            Task { await conversationController.send(text, to: conversationID, repliedTo: target.messageID) }
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

/// The bar's own surface: one square-edged, full-bleed slab under the quote and the controls,
/// running past the safe area to the bottom of the display.
///
/// Permanent *geometry*, and that is the point. The reply surface used to be a rounded panel that
/// appeared behind the bar and left again, and no amount of curve-matching stopped it reading as a
/// second object crossfading over the messages — because it *was* one. Nothing here mounts or
/// unmounts: the slab is always drawn, always full width, always pinned to the bottom. A reply
/// changes one thing about it — how tall it is — so what moves is the bar itself rather than
/// something arriving over the messages.
///
/// The colour is one of the things a reply must *not* change. `background` is (25,25,26) and the
/// keyboard's own container paints within a level of that, which is why the slab and the keyboard
/// read as one surface. Lifting the slab to `backgroundSecondary` (37,37,38) for a reply drew a hard
/// horizontal line across the screen at the keyboard's top edge — not a gap in the bleed, which
/// already runs past the safe area, but a colour step against a system surface we cannot repaint. So
/// the elevation a reply needs goes on the quote instead; see ``ComposerReplyStrip/Style``.
private struct BarSurfaceBackground: ViewModifier {

    /// How far the surface paints below the bar's own bottom edge.
    ///
    /// The keyboard's top corners are rounded, and what shows through them is whatever sits behind
    /// the keyboard — which left a hard-edged notch of chat background at each bottom corner of the
    /// bar, about 24×25pt on an iPhone 16 Pro. Painting past the bar's edge fills them. Everywhere
    /// else this is hidden by the keyboard, or by the home-indicator area when the keyboard is down,
    /// so overshooting the radius costs nothing.
    private static let keyboardCornerBleed: CGFloat = 32

    func body(content: Content) -> some View {
        // Top-aligned so the negative padding hangs the extra height below the bar rather than
        // splitting it, which would paint over the transcript.
        content.background(alignment: .top) {
            BarSurface.restingFade
            // Absorbed by the fade's opaque tail, so the dissolve at the top edge keeps its height
            // whatever the bleed is.
            .padding(.bottom, -Self.keyboardCornerBleed)
            // Scope the safe-area bleed to the bottom edge only. The bar is a measured,
            // keyboard-guide-pinned hosted view; an all-edges ignore makes the bar read as
            // extending to the screen bottom, which collapses the scroll-content inset by the
            // home-indicator height and drops the newest message under the bar.
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// What the bar's surface is made of.
///
/// The slab is not a slab at its top edge: it ramps from the chat background up to nothing over
/// ``fadeHeight``, so a message scrolling under the bar dissolves into it rather than meeting a hard
/// line. Opaque instead, the bar reads as a toolbar bolted across the transcript.
///
/// One paint, in every state — see `BarSurfaceBackground` for why a reply may not change it. It is
/// painted in two places: the bar draws it, and the screen paints the same colour below the bar so
/// it reaches the bottom of the display. See `BarSurfaceFloor`.
enum BarSurface {

    /// How far the resting surface takes to ramp from nothing to the chat background — half the
    /// resting bar, which is where the proportional gradient this replaces put the boundary.
    ///
    /// Fixed rather than a fraction of the bar, because a fraction ties the dissolve to the draft: a
    /// four-line message doubled the fade and softened the transcript twice as far up the screen,
    /// for no reason a reader can see.
    static let fadeHeight: CGFloat = 33

    /// The composer at rest: clear at the top edge, chat background below it. The flexible tail is
    /// what lets the slab bleed past the safe area without stretching the ramp.
    static var restingFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .backgroundMain], startPoint: .top, endPoint: .bottom)
                .frame(height: fadeHeight)
            Color.backgroundMain
        }
    }

}

/// The bar surface's continuation below the bar, painted by the screen.
///
/// The bar is a hosted view held off the bottom safe area, so its own background stops at the home
/// indicator. The screen owns the rest; filling it with the same colour is what makes the bar read as
/// running off the bottom of the display instead of floating above it.
///
/// It paints the whole screen, not just the strip, and is placed behind the transcript — which is
/// opaque — so only the region below the transcript's own bottom edge is ever visible. Sizing it to
/// the inset instead does not work: `ignoresSafeArea` grows the region offered to a *flexible* view,
/// and a view already fixed to a height keeps that height and stays inside the safe area.
///
struct BarSurfaceFloor: View {

    var body: some View {
        Color.backgroundMain
            .ignoresSafeArea(.container, edges: .bottom)
            .allowsHitTesting(false)
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
    /// Tip chats always show it minimized; ordinary chats expand at rest.
    var alwaysMinimized: Bool = false
    /// Replaces "Send <symbol>" while expanded. A tip chat names the tip
    /// instead of the currency, because the amount is chosen on the next screen.
    var expandedTitle: String?
    let action: () -> Void

    /// The compact glass "€" presentation: while composing, or always in a tip
    /// chat. The whole morph (label, fill, width, color) keys off this.
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
