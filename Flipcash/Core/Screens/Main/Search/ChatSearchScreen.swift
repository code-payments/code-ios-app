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

    /// Whether this screen is the one in front. The search tab stays alive while other tabs show,
    /// so leaving and returning to it is what counts as closing and reopening search.
    var isActive = true

    @Environment(\.scenePhase) private var scenePhase

    @State private var model: ChatSearchModel?
    /// The chip whose results are showing; trails the selected chip while they fade through.
    @State private var shownScope: ChatSearchScope = .all
    @State private var resultsOpacity = 1.0
    @State private var resultsScroll = ScrollPosition(edge: .top)
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        switch chrome {
        case .pushed:
            screen {
                SearchBar(
                    query: queryBinding,
                    isFocused: $isFieldFocused,
                    onChats: { dismiss() },
                    onClose: { dismiss() }
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
                // Recent reads the recents store, not the model, so it draws on the first frame
                // instead of popping in once the model has loaded.
                if let model, !model.isIdle {
                    results(model)
                        .transition(.opacity)
                } else {
                    RecentSection(conversations: recentConversations, onOpen: open)
                        .transition(.opacity)
                }
                bottomBar()
            }
            .animation(.easeInOut(duration: 0.2), value: model?.isIdle ?? true)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: isActive) { _, _ in startFresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { startFresh() }
        }
        .task {
            guard model == nil else { return }
            let model = makeModel()
            self.model = model
            await model.load()
        }
    }

    /// Results under the chips, which ride the scroll view's top edge so rows blur out beneath them.
    private func results(_ model: ChatSearchModel) -> some View {
        ScrollView {
            ChatSearchResults(model: model, scope: shownScope, onOpenChat: open, onOpenMessage: open, onOpenLink: open, onOpenCurrency: openCurrency)
                .opacity(resultsOpacity)
        }
        .scrollPosition($resultsScroll)
        .scrollEdgeBar(.top) {
            ScopeChips(selection: Binding(get: { model.scope }, set: { model.scope = $0 }))
                .animation(.easeInOut(duration: 0.2), value: model.scope)
        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: model.scope) { _, scope in fadeResults(to: scope) }
    }

    /// Fades the old results out before the new ones come in, matching Android, so rows in the
    /// same place never show through each other. A later chip tap wins over an earlier one.
    private func fadeResults(to scope: ChatSearchScope) {
        withAnimation(.easeIn(duration: 0.09)) {
            resultsOpacity = 0
        } completion: {
            guard model?.scope == scope else { return }
            shownScope = scope
            resultsScroll.scrollTo(edge: .top)
            withAnimation(.easeOut(duration: 0.15)) {
                resultsOpacity = 1
            }
        }
    }

    /// Every open starts from an empty field, the All chip and the top of Recent. Recent's saved
    /// history is not search input and stays.
    private func startFresh() {
        model?.reset()
        shownScope = .all
        resultsOpacity = 1
        resultsScroll.scrollTo(edge: .top)
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

    /// Currencies live on the wallet, so the Money tab comes forward with the currency as its only
    /// screen, and back lands on the wallet rather than on Search.
    ///
    /// The keyboard goes down first, so it doesn't slide away over the currency.
    private func openCurrency(_ mint: MintMetadata) {
        guard isFieldFocused else {
            showCurrency(mint)
            return
        }
        Task {
            await KeyboardHideWaiter().wait { isFieldFocused = false }
            showCurrency(mint)
        }
    }

    private func showCurrency(_ mint: MintMetadata) {
        // Pushed on the Chat tab (iOS < 26, and wherever the search tab isn't used), Search is the
        // top of that stack; pop it so the Chat tab doesn't come back showing Search. The iOS 26
        // search tab has its own stack the router doesn't track, and the tab switch leaves it.
        if chrome == .pushed {
            router.pop(on: .tips)
        }
        router.navigate(to: .currencyInfo(mint.address))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Runs `resign` and returns once the keyboard is out of sight. `keyboardDidHide` lands well after
/// that, since the hide is a spring whose tail runs on unseen below the screen, so this waits on
/// `keyboardWillHide` plus part of its animation instead. A hardware keyboard posts neither, so it
/// gives up after `timeout`.
@MainActor
private final class KeyboardHideWaiter {
    /// The share of the hide animation after which the keyboard is visually gone.
    private static let visibleShare = 0.6

    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: NSObjectProtocol?

    func wait(timeout: Duration = .milliseconds(450), resign: () -> Void) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0
                MainActor.assumeIsolated { self?.finish(after: .seconds(duration * Self.visibleShare)) }
            }
            resign()
            finish(after: timeout)
        }
    }

    private func finish(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.finish()
        }
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        continuation.resume()
    }
}

// MARK: - Search bar -

/// The bottom bar: back to Chats, the query field with its clear button, and close.
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

                if !query.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("chat-search-clear")
                }
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
        // The unselected chips are outlines only, so rows scrolling under them need a backdrop that
        // fades them out before they reach the chips.
        .background {
            LinearGradient(
                stops: [
                    .init(color: .backgroundMain, location: 0),
                    .init(color: .backgroundMain, location: 0.65),
                    .init(color: .backgroundMain.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.bottom, -32)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
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
