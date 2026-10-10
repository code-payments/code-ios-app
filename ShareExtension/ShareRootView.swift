//
//  ShareRootView.swift
//  ShareExtension
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct ShareRootView: View {

    let model: ShareModel

    @State private var selected: Conversation?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Share to Flipcash")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancel() }
                    }
                }
        }
        .task { model.load() }
        .sheet(item: $selected) { chat in
            ShareComposeView(model: model, chat: chat)
        }
        .onChange(of: model.preselectedID) { _, id in
            guard selected == nil, let id, let chat = model.chats.first(where: { $0.id == id }) else { return }
            selected = chat
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .signedOut:
            ShareMessageView(title: "Open Flipcash to sign in", detail: "Sign in to the app, then share again.")
        case .chatsUnavailable:
            ShareMessageView(title: "Open Flipcash to refresh", detail: "Your chats aren't ready yet. Open the app once, then share again.")
        case .ready where model.chats.isEmpty:
            ShareMessageView(title: "No chats yet", detail: "Start a chat in Flipcash, then share again.")
        case .ready:
            List(model.chats) { chat in
                Button { selected = chat } label: {
                    ShareChatRow(name: model.displayName(for: chat), avatar: model.avatar(for: chat))
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }
}

extension Conversation: @retroactive Identifiable {}

private struct ShareChatRow: View {

    let name: String
    let avatar: ShareAvatar

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(id: avatar.id, displayName: name, imageData: avatar.imageData, blurhash: avatar.blurhash, size: 40)
                .accessibilityHidden(true)
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

struct ShareMessageView: View {

    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
