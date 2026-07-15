//
//  ConversationBottomBar.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Shared state for the unified bottom bar: the message draft plus the
/// focus-driven `isComposing` flag that drives the Send Cash morph and the
/// screen's interactive-dismiss gate.
@MainActor @Observable final class ConversationBarModel {
    var isComposing = false
    var draft = ""

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Single spring driving the whole bar: the button morph, the composer's
/// appearance when the chat materializes, and the send-arrow pop.
let barMorphSpring = Animation.spring(duration: 0.35, bounce: 0.2)

/// The unified bottom bar: Send Cash (morphing) beside the message field.
/// Full-width Send Cash alone until the chat exists server-side.
struct ConversationBottomBar: View {

    let showsSendCash: Bool
    let chatExists: Bool
    let conversationID: ConversationID?
    let symbol: String
    let onSendCash: () -> Void
    @Bindable var model: ConversationBarModel

    var body: some View {
        let content = HStack(alignment: .bottom, spacing: 10) {
            if showsSendCash {
                SendCashMorphButton(
                    symbol: symbol,
                    composing: model.isComposing,
                    fullWidth: !chatExists,
                    action: onSendCash
                )
            }
            if chatExists {
                ConversationComposer(conversationID: conversationID, model: model)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(barMorphSpring, value: chatExists)

        // Adjacent glass elements must share a sampling container on iOS 26 —
        // glass cannot sample other glass; spacing matches the HStack's.
        return Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 10) { content }
            } else {
                content
            }
        }
        .modifier(BarGradientBackground())
    }
}

/// The glass type box: a multiline field with a send button that appears once
/// there's text. Swiping the chat down lowers the keyboard and the box.
struct ConversationComposer: View {

    let conversationID: ConversationID?
    @Bindable var model: ConversationBarModel

    @Environment(ConversationController.self) private var conversationController
    @FocusState private var isFocused: Bool

    /// Send button scale-in/out as text appears/clears.
    private static let sendButtonSpring = Animation.spring(duration: 0.17, bounce: 0.34)

    var body: some View {
        let field = HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $model.draft, axis: .vertical)
                .font(.appTextMessage)
                .foregroundStyle(Color.textMain)
                .tint(.white)
                .lineLimit(1...5)
                .focused($isFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 34)

            if model.canSend {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.default(size: 16, weight: .bold))
                        .foregroundStyle(Color.textAction)
                        .frame(width: 34, height: 34)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("send-message-button")
                // Pop from 60% + fade, so the opacity ramp actually reads
                // (scaling from 0 hides the fade behind a tiny speck).
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(Self.sendButtonSpring, value: model.canSend)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)

        // Liquid-glass background on iOS 26; ultra-thin material below.
        return Group {
            if #available(iOS 26, *) {
                field.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            } else {
                field.background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            }
        }
        // Focus is the single source of `isComposing` — the button morph and the
        // screen's interactive-dismiss gate both key off it. Losing focus
        // (keyboard swiped down) ends composing.
        .onChange(of: isFocused) { _, focused in
            withAnimation(barMorphSpring) { model.isComposing = focused }
            if !focused, let conversationID {
                conversationController.stopSelfTyping(in: conversationID)
            }
        }
        .onChange(of: model.draft) { _, text in
            guard let conversationID else { return }
            conversationController.draftDidChange(text, in: conversationID)
        }
    }

    private func send() {
        guard let conversationID else { return }
        let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.draft = ""
        isFocused = true
        // Fire-and-forget: the message inserts optimistically and resolves on its own, so the composer
        // stays ready immediately — the user can keep sending (especially offline) without waiting for
        // each round-trip. Clearing the draft up front makes a double-tap a no-op (empty text).
        Task { await conversationController.send(text, to: conversationID) }
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
            // Scope the bleed to the bottom edge only. The bar is the measured
            // content of the transcript's bottom `.safeAreaInset`; an all-edges
            // ignore makes the bar read as extending to the screen bottom, which
            // collapses the scroll-content inset by the home-indicator height and
            // drops the newest message under the bar.
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// The Send Cash button, rendered as a white "Send €" pill at rest and a
/// compact glass "€" square while composing.
// One persistent view: the morph animates its properties (prefix text, fill,
// width, color) in lockstep — splitting the two states into separate views
// would crossfade instead of morphing.
struct SendCashMorphButton: View {

    let symbol: String
    let composing: Bool
    /// Spans the bar when the composer isn't available (no chat yet).
    let fullWidth: Bool
    let action: () -> Void

    /// Matches the composer field: 34pt min field height + 2×8pt padding.
    private static let height: CGFloat = 50
    private static let cornerRadius: CGFloat = 14

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !composing {
                    Text("Send")
                        .transition(.opacity)
                }
                Text(symbol)
            }
            .font(.appTextMedium)
            .foregroundStyle(composing ? Color.textMain : Color.textAction)
            // The label must never reflow to "Se…" mid-morph; overflow is
            // clipped by the shape instead.
            .fixedSize()
            .padding(.horizontal, composing ? 0 : 20)
            .frame(minWidth: Self.height)
            .frame(maxWidth: fullWidth && !composing ? .infinity : nil)
            .frame(height: Self.height)
        }
        .buttonStyle(.plain)
        // White fill above the glass base: fading it out is the white → glass
        // change, without ever swapping views.
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(Color.action)
                .opacity(composing ? 0 : 1)
        }
        .modifier(GlassBase(cornerRadius: Self.cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .accessibilityLabel("Send Cash")
        .accessibilityIdentifier("send-cash-button")
    }
}

/// Liquid-glass base on iOS 26; ultra-thin material below (the composer's split).
private struct GlassBase: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

#Preview("Morph") {
    @Previewable @State var composing = false
    ZStack {
        Color.backgroundMain.ignoresSafeArea()
        VStack {
            Spacer()
            HStack(spacing: 10) {
                SendCashMorphButton(symbol: "€", composing: composing, fullWidth: false) {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { composing.toggle() }
                }
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.1))
                    .frame(height: 50)
            }
            .padding(12)
        }
    }
}
