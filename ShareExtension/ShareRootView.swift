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

    @State private var limitHit = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(Color(.systemGroupedBackground))
        .task { model.load() }
    }

    private var header: some View {
        ZStack {
            Text("Send to").font(.headline)
            HStack {
                Button { model.cancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.secondarySystemFill), in: Circle())
                }
                .accessibilityLabel("Cancel")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxHeight: .infinity)
        case .signedOut:
            ShareMessageView(title: "Open Flipcash to sign in", detail: "Sign in to the app, then share again.")
        case .chatsUnavailable:
            ShareMessageView(title: "Open Flipcash to refresh", detail: "Your chats aren't ready yet. Open the app once, then share again.")
        case .ready where model.chats.isEmpty:
            ShareMessageView(title: "No chats yet", detail: "Start a chat in Flipcash, then share again.")
        case .ready:
            picker
        }
    }

    private var picker: some View {
        @Bindable var model = model
        let sections = model.sections
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                searchField
                if !sections.suggested.isEmpty {
                    section("Suggested", ids: sections.suggested)
                }
                if sections.isSearching && sections.recent.isEmpty {
                    Text("No chats match \u{201C}\(model.query)\u{201D}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else if !sections.recent.isEmpty {
                    section(sections.isSearching ? "Chats" : "Recent chats", ids: sections.recent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.warning, trigger: limitHit)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.recipients.isEmpty {
                ShareComposeBar(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: model.recipients.isEmpty)
    }

    private var searchField: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $model.query)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private func section(_ title: String, ids: [ConversationID]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(ids, id: \.self) { id in
                    if let chat = model.chat(id) {
                        Button {
                            if model.toggle(id) == .limitReached { limitHit += 1 }
                        } label: {
                            ShareChatRow(
                                name: model.displayName(for: chat),
                                avatar: model.avatar(for: chat),
                                isSelected: model.recipients.contains(id)
                            )
                        }
                        .buttonStyle(.plain)
                        if id != ids.last {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

extension Conversation: @retroactive Identifiable {}

private struct ShareChatRow: View {

    let name: String
    let avatar: ShareAvatar
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(id: avatar.id, displayName: name, imageData: avatar.imageData, blurhash: avatar.blurhash, size: 40)
                .accessibilityHidden(true)
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(isSelected ? Color.success : Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        .frame(maxHeight: .infinity)
    }
}
