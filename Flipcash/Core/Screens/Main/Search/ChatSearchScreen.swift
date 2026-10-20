//
//  ChatSearchScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Chats Search: Recent while the query is empty, then results under pinned chips.
struct ChatSearchScreen: View {

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(Session.self) private var session
    @Environment(Container.self) private var container
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    /// Where the search field lives.
    enum Chrome {
        /// Pushed onto the Chat tab, with its own field and buttons at the bottom.
        case pushed
        /// The iOS 26 search tab, whose field is the system one in the tab bar.
        case tab
    }

    var chrome: Chrome = .pushed

    /// Where a result opens. Nil pushes onto the stack this screen is on.
    var navigate: ((AppRouter.Destination) -> Void)?

    @State private var model: ChatSearchModel?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        switch chrome {
        case .pushed:
            screen {
                SearchBar(
                    query: queryBinding,
                    isFocused: $isFieldFocused,
                    onChats: { dismiss() },
                    onClose: close
                )
            }
        case .tab:
            screen { EmptyView() }
                .searchable(text: queryBinding, prompt: "Search")
                .searchFocused($isFieldFocused)
        }
    }

    private func screen(@ViewBuilder bottomBar: () -> some View) -> some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                if let model {
                    content(model)
                } else {
                    Spacer()
                }
                bottomBar()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard model == nil else { return }
            let model = makeModel()
            self.model = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ model: ChatSearchModel) -> some View {
        if model.isIdle {
            RecentSection(conversations: recentConversations, onOpen: open)
                .transition(.opacity)
        } else {
            VStack(spacing: 0) {
                ScopeChips(selection: Binding(get: { model.scope }, set: { model.scope = $0 }))
                ScrollView {
                    ChatSearchResults(model: model, onOpenChat: open, onOpenMessage: open, onOpenLink: open, onOpenCurrency: openCurrency)
                        .id(model.scope)
                        .transition(.opacity)
                }
                .scrollDismissesKeyboard(.immediately)
                .animation(.easeInOut(duration: 0.2), value: model.scope)
            }
        }
    }

    private var queryBinding: Binding<String> {
        Binding(get: { model?.query ?? "" }, set: { model?.query = $0 })
    }

    /// The chats opened from search, newest first, leaving out any no longer in the feed.
    private var recentConversations: [Conversation] {
        sessionContainer.chatSearchRecents.conversationIDs.compactMap { conversationController.conversation(withID: $0) }
    }

    private func makeModel() -> ChatSearchModel {
        let controller = conversationController
        let database = sessionContainer.database
        let session = session
        let discovered = sessionContainer.discoveredCurrencies
        let held: @MainActor () -> [MintMetadata] = {
            session.balances.compactMap { session.storedMintMetadata(for: $0.mint)?.metadata }
        }
        return ChatSearchModel(
            conversations: { controller.conversations },
            loadMessages: { try await database.searchableMessages() },
            currencySearch: LocalCurrencyNameSearch(candidates: { @MainActor in held() + discovered.mints }),
            chatName: { controller.displayName(for: $0) },
            chatHandles: { conversation in
                conversation.members.compactMap { $0.userID == controller.selfUserID ? nil : $0.username?.value }
            },
            senderName: { senderID, conversationID in
                if senderID == controller.selfUserID { return "you" }
                return controller.conversation(withID: conversationID)?
                    .members.first { $0.userID == senderID }?
                    .displayName
                    .nilIfEmpty
            }
        )
    }

    private func close() {
        if model?.query.isEmpty == false {
            model?.query = ""
        } else {
            dismiss()
        }
    }

    /// Drops focus before pushing: UIKit otherwise restores the field as first responder on the way
    /// back, while the chat that ignores the keyboard safe area is still on top, and the bar comes
    /// back behind the keyboard.
    private func push(_ destination: AppRouter.Destination) {
        isFieldFocused = false
        if let navigate {
            navigate(destination)
        } else {
            router.push(destination)
        }
    }

    private func open(_ conversation: Conversation) {
        sessionContainer.chatSearchRecents.record(conversation.id)
        push(.tipConversation(conversation.id))
    }

    private func open(_ hit: ChatSearchMessageHit) {
        sessionContainer.chatSearchRecents.record(hit.conversationID)
        push(.chatMessage(hit.conversationID, MessageLanding(messageID: hit.messageID, returnTo: nil)))
    }

    private func open(_ link: ChatSearchLink) {
        ExternalLinkOpener(session: session, trustedWebsites: container.trustedWebsites).open(link.url)
    }

    private func openCurrency(_ mint: MintMetadata) {
        push(.currencyInfo(mint.address))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Search bar -

/// The bottom bar: back to Chats, the query field, and close.
private struct SearchBar: View {

    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding
    let onChats: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CircleButton(systemImage: "bubble.left.and.bubble.right", label: "Chats", action: onChats)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textSecondary)
                TextField("Search", text: $query)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .focused(isFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("chat-search-field")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.backgroundRow, in: Capsule())

            CircleButton(systemImage: "xmark", label: "Close", action: onClose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct CircleButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.textMain)
                .frame(width: 52, height: 52)
                .background(Color.backgroundRow, in: Circle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Chips -

private struct ScopeChips: View {

    @Binding var selection: ChatSearchScope

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChatSearchScope.allCases, id: \.self) { scope in
                    Button(scope.title) {
                        selection = scope
                    }
                    .buttonStyle(.selectableChip(isSelected: selection == scope))
                    .accessibilityIdentifier("chat-search-chip-\(scope.title)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Recent -

private struct RecentSection: View {

    let conversations: [Conversation]
    let onOpen: (Conversation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search")
                .font(.appDisplaySmall)
                .foregroundStyle(Color.textMain)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            if !conversations.isEmpty {
                Text("Recent")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(conversations) { conversation in
                            RecentItem(conversation: conversation) { onOpen(conversation) }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecentItem: View {

    let conversation: Conversation
    let onTap: () -> Void

    @Environment(ConversationController.self) private var conversationController

    var body: some View {
        let name = conversationController.displayName(for: conversation)
        Button(action: onTap) {
            VStack(spacing: 6) {
                ChatSearchAvatar(conversation: conversation, size: 64)
                Text(name.split(separator: " ").first.map(String.init) ?? name)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}

// MARK: - Avatar -

/// A chat's avatar: the group's picture, or the other person's in a DM.
struct ChatSearchAvatar: View {

    let conversation: Conversation
    var size: CGFloat = 44

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        let avatar = conversation.avatar(excluding: conversationController.selfUserID)
        ContactAvatarView(
            id: conversation.id.description,
            displayName: conversationController.displayName(for: conversation),
            imageData: sessionContainer.profileAvatars.data(for: avatar.subject),
            blurhash: avatar.picture?.thumbnailBlurhash,
            size: size
        )
        .task(id: avatar.subject) {
            await sessionContainer.profileAvatars.load(avatar.subject, picture: avatar.picture)
        }
    }
}
