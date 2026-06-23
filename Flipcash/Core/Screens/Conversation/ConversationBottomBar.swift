//
//  ConversationBottomBar.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Shared state for the action bar and the composer. They live in separately-anchored
/// hosted views (safe area vs keyboard), so they share state through this model rather
/// than a parent; each reads `isComposing` to animate its own fade.
@MainActor @Observable final class ConversationBarModel {
    var isComposing = false
    var draft = ""
    var isSending = false

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }
}

/// Action bar ⇄ composer swap — the button group springs in/out (scaling
/// from 95%) while the composer fades.
private let barSwapSpring = Animation.spring(duration: 0.27, bounce: 0.31)

/// Send Cash alone until the chat exists, then Send Cash + Send Message.
struct ConversationActionBar: View {

    let showsSendCash: Bool
    let showsSendMessage: Bool
    let onSendCash: () -> Void
    let model: ConversationBarModel

    var body: some View {
        HStack(spacing: 10) {
            if showsSendCash {
                Button("Send Cash", action: onSendCash)
                    .buttonStyle(.filled)
            }
            if showsSendMessage {
                // Material-only frosted button (no fill) — matches the .filled
                // metrics (full width, 60pt tall, 6pt radius, appTextMedium).
                Button(action: { withAnimation(barSwapSpring) { model.isComposing = true } }) {
                    Text("Send Message")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.buttonHeight)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Metrics.buttonRadius))
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(barSwapSpring, value: showsSendMessage)
        // Scales + fades out in place while composing. The bar is pinned to the safe
        // area (in the UIKit screen), so it never rides the keyboard.
        .scaleEffect(model.isComposing ? 0.95 : 1)
        .modifier(BarGradientBackground())
        .opacity(model.isComposing ? 0 : 1)
        .animation(barSwapSpring, value: model.isComposing)
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
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .modifier(BarGradientBackground())
        .opacity(model.isComposing ? 1 : 0)
        .animation(barSwapSpring, value: model.isComposing)
        // Focus follows composing. The field is already mounted, so this is reliable —
        // `.onAppear` would raise the keyboard on screen entry. Losing focus (keyboard
        // swiped down) ends composing.
        .onChange(of: model.isComposing) { _, composing in isFocused = composing }
        .onChange(of: isFocused) { _, focused in if !focused { withAnimation(barSwapSpring) { model.isComposing = false } } }
    }

    private func send() {
        guard let conversationID else { return }
        let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isSending else { return }
        model.isSending = true
        model.draft = ""
        isFocused = true
        Task {
            await conversationController.send(text, to: conversationID)
            model.isSending = false
        }
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
