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
            .background(Color.textMain.opacity(model.canSend || model.isSending ? 1 : 0.4), in: Capsule())
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
                .foregroundStyle(.secondary)
        }
        if case .sending(let chat, let total) = model.sendState, total > 1 {
            Text("Sending \(chat) of \(total)")
                .font(.appTextCaption)
                .foregroundStyle(.secondary)
        }
        if let progress = model.progress, case .failed = model.sendState {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(progress.failed, id: \.self) { id in
                    if let chat = model.chat(id), case .failed(let message, _) = progress.statuses[id] {
                        Text("\(model.displayName(for: chat)): \(message)")
                            .font(.appTextCaption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
