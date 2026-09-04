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

/// Metrics shared by the field and the button beside it so their heights can't
/// desync. Deliberately not `Metrics.buttonHeight`/`buttonRadius` — beside the
/// field the controls are field-sized, not standard-button-sized.
private enum BarMetrics {
    static let fieldMinHeight: CGFloat = 34
    static let fieldVerticalPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 14
    /// The height of every bar control: a single-line field plus its padding.
    static let contentHeight: CGFloat = fieldMinHeight + fieldVerticalPadding * 2
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
                    composing: model.isComposing,
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
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(barMorphSpring, value: chatExists)
        .animation(barMorphSpring, value: composer.isEditing)

        // No shared GlassEffectContainer: the composer's glass is a background
        // layer behind an editable text field, and a container composites its
        // glass above sibling content — drawing the glass over the typed text.
        // The Send Cash button and the field are separate pills 10pt apart, so
        // they don't need to sample each other.
        return content
            .modifier(BarGradientBackground())
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
        case .replying:
            guard let text = composer.submission else { return }
            composer.clear()
            isFocused = true
            Task { await conversationController.send(text, to: conversationID) }
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

/// Bottom-edge fade so transcript content scrolling under the bar dissolves into
/// the background.
private struct BarGradientBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            LinearGradient(
                gradient: Gradient(colors: [Color.backgroundMain, Color.backgroundMain, .clear]),
                startPoint: .bottom,
                endPoint: .top
            )
            // Scope the bleed to the bottom edge only. The bar is a measured,
            // keyboard-guide-pinned hosted view; an all-edges ignore makes the
            // bar read as extending to the screen bottom, which collapses the
            // scroll-content inset by the home-indicator height and drops the
            // newest message under the bar.
            .ignoresSafeArea(edges: .bottom)
        }
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
