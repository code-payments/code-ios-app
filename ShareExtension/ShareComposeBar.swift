//
//  ShareComposeBar.swift
//  ShareExtension
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The bar that slides up once a chat is picked: the shared images, the message field, who it goes
/// to, and Send.
struct ShareComposeBar: View {

    let model: ShareModel

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            failures

            HStack(alignment: .top, spacing: 10) {
                if !model.thumbnails.isEmpty {
                    thumbnails
                }
                TextField("Add a message…", text: $model.text, axis: .vertical)
                    .font(.appTextMessage)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 20))
                    .disabled(model.isSending)
            }

            HStack(spacing: 12) {
                Text(model.recipientSummary)
                    .font(.appTextSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                sendButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var thumbnails: some View {
        ZStack {
            ForEach(Array(model.thumbnails.prefix(3).enumerated().reversed()), id: \.element.id) { offset, thumbnail in
                Image(decorative: thumbnail.image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemBackground), lineWidth: 1.5))
                    .offset(x: CGFloat(offset) * 5, y: CGFloat(offset) * -3)
            }
            if model.thumbnails.count > 1 {
                Text("\(model.thumbnails.count)")
                    .font(.appTextHeading)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .background(.black.opacity(0.6), in: Capsule())
                    .offset(x: 16, y: 16)
            }
        }
        .frame(width: 54, height: 48)
        .padding(.top, 2)
        .accessibilityLabel("\(model.thumbnails.count) attached")
    }

    private var sendButton: some View {
        Button {
            model.send()
        } label: {
            Group {
                if model.isSending {
                    ProgressView().tint(Color.textAction)
                } else {
                    Text(isRetry ? "Retry" : "Send").font(.default(size: 17, weight: .medium))
                }
            }
            .foregroundStyle(Color.textAction)
            .frame(minWidth: 64, minHeight: 36)
            .padding(.horizontal, 6)
            .background(Color.action.opacity(model.canSend || model.isSending ? 1 : 0.4), in: Capsule())
            // The 36pt capsule takes a 44pt hit area without growing.
            .contentShape(Rectangle().inset(by: -4))
        }
        .disabled(!model.canSend)
    }

    private var isRetry: Bool {
        if case .failed = model.sendState { true } else { false }
    }

    @ViewBuilder
    private var failures: some View {
        if model.input.droppedImageCount > 0 {
            Text("Only the first \(ShareInput.maxImages) images are sent.")
                .font(.appTextCaption)
                .shareSecondaryInk()
        }
        if case .sending(let chat, let total) = model.sendState, total > 1 {
            Text("Sending \(chat) of \(total)")
                .font(.appTextCaption)
                .shareSecondaryInk()
        }
        if let progress = model.progress, case .failed = model.sendState {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(progress.failed, id: \.self) { id in
                    if let chat = model.chat(id), case .failed(let message, _) = progress.statuses[id] {
                        Text("\(model.displayName(for: chat)): \(message)")
                            .font(.appTextCaption)
                            .foregroundStyle(Color.shareFailure)
                    }
                }
            }
        }
    }
}

private extension Color {

    /// A failed recipient's line: system red in dark, `textError`'s deeper red in light, where
    /// system red reads at 3.2:1 on the bar.
    @MainActor static let shareFailure = Color(light: .textError, dark: .red)
}

extension View {

    /// Draws the extension's secondary text: the system's hierarchical secondary in dark, and
    /// `textSecondary` in light, where the system's reads at 3.3:1 on the share sheet.
    func shareSecondaryInk() -> some View {
        modifier(ShareSecondaryInk())
    }
}

private struct ShareSecondaryInk: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        switch colorScheme {
        case .dark:
            content.foregroundStyle(.secondary)
        case .light:
            content.foregroundStyle(Color.textSecondary)
        @unknown default:
            content.foregroundStyle(Color.textSecondary)
        }
    }
}
