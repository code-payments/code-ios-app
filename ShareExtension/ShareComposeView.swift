//
//  ShareComposeView.swift
//  ShareExtension
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

struct ShareComposeView: View {

    let model: ShareModel
    let chat: Conversation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if !model.thumbnails.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.thumbnails) { thumbnail in
                                Image(decorative: thumbnail.image, scale: 1)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .scrollClipDisabled()
                    if model.input.droppedImageCount > 0 {
                        Text("Only the first \(ShareInput.maxImages) images are sent.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                TextField(model.thumbnails.isEmpty ? "Message" : "Add a caption", text: $model.text, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSending)

                status

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(model.displayName(for: chat))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                        .disabled(model.isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isRetry ? "Retry" : "Send") { model.send(to: chat) }
                        .disabled(!canSend)
                }
            }
        }
        .interactiveDismissDisabled(model.isSending)
        .presentationDetents([.medium, .large])
    }

    private var isRetry: Bool {
        if case .failed = model.sendState { true } else { false }
    }

    private var canSend: Bool {
        if model.isSending { return false }
        if case .failed(_, let canRetry) = model.sendState, !canRetry { return false }
        return !model.thumbnails.isEmpty || !model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var status: some View {
        switch model.sendState {
        case .idle:
            EmptyView()
        case .sending(let step, let total):
            HStack(spacing: 8) {
                ProgressView()
                Text(total > 1 ? "Sending \(step) of \(total)" : "Sending")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message, _):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }
}
