//
//  ConversationScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import Combine
import FlipcashCore
import FlipcashUI

/// How a conversation is reached: an existing DM chat from the Chats section,
/// or a synced contact whose chat may not exist yet — the first cash payment
/// creates it server-side.
nonisolated enum ConversationContext: Hashable {
    case existing(ConversationID)
    case contact(ResolvedContact)
}

/// A DM conversation: an iMessage-style transcript over a Send Cash / Send
/// Message action bar. Reads live messages from `ConversationController`,
/// which owns the single event stream. For a contact without a chat the
/// transcript stays empty and only Send Cash shows; once the first payment
/// creates the chat, the chat ID resolves live from the synced directory and
/// Send Message appears.
struct ConversationScreen: View {

    let context: ConversationContext

    @Environment(ConversationController.self) private var conversationController
    @Environment(ContactSyncController.self) private var contactSyncController
    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController

    @State private var draft = ""
    @State private var isSending = false
    @State private var hasLoaded = false
    @State private var didInitialRead = false
    @State private var isComposing = false
    @State private var hasAppeared = false
    @State private var navBarWidth: CGFloat = 0
    @FocusState private var isComposerFocused: Bool

    /// What the transcript renders. Synced from the controller only while this
    /// screen is frontmost, so messages that land while the amount screen
    /// covers it (the cash card after a send) insert with a visible animation
    /// on return instead of already sitting in the list.
    @State private var displayedMessages: [ConversationMessage] = []
    @State private var isTopmost = false

    /// Horizontal space the back button (leading) reserves on each side of the
    /// centered title item, so the avatar + name can left-align inside a
    /// centered, full-width principal stack.
    private static let titleSideInset: CGFloat = 72

    /// The synced contact for the counterpart, resolved live from the directory
    /// so a `dmChatID` stored after the first payment flows in. Falls back to
    /// the pushed snapshot when the directory hasn't resolved yet.
    private var contact: ResolvedContact? {
        let directory = contactSyncController.resolvedContacts.onFlipcash
        switch context {
        case .contact(let contact):
            return directory.first { $0.id == contact.id } ?? contact
        case .existing(let conversationID):
            return directory.first { $0.dmChatID == conversationID.data }
        }
    }

    private var conversationID: ConversationID? {
        switch context {
        case .existing(let conversationID):
            return conversationID
        case .contact:
            return contact?.dmChatID.map(ConversationID.init(data:))
        }
    }

    /// Whether the DM chat actually exists server-side. Matched contacts carry
    /// a pre-assigned `dmChatID` before any payment (the first intent needs it),
    /// so the ID alone doesn't mean the chat was created — require it to be in
    /// the feed or to have messages.
    private var chatExists: Bool {
        guard let conversationID else { return false }
        switch context {
        case .existing:
            return true
        case .contact:
            return conversationController.conversations.contains { $0.id == conversationID }
                || !conversationController.messages(for: conversationID).isEmpty
        }
    }

    private var title: String {
        if let conversationID {
            return conversationController.displayName(forConversationID: conversationID)
        }
        return contact?.displayName ?? ConversationController.fallbackCounterpartName
    }

    private var messages: [ConversationMessage] {
        guard let conversationID else { return [] }
        return conversationController.messages(for: conversationID)
    }

    var body: some View {
        Group {
            if chatExists && !hasLoaded && messages.isEmpty {
                LoadingView(color: .textMain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ConversationTranscript(
                    messages: displayedMessages,
                    selfUserID: conversationController.selfUserID,
                    onBackgroundTap: dismissKeyboard
                )
            }
        }
        .background(Color.backgroundMain)
        .safeAreaInset(edge: .bottom) {
            ConversationBottomBar(
                showsSendCash: contact != nil,
                showsSendMessage: chatExists,
                isComposing: $isComposing,
                draft: $draft,
                focus: $isComposerFocused,
                canSend: canSend,
                onSendCash: sendCash,
                onSendText: send
            )
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ConversationTitleItem(
                    title: title,
                    contact: contact,
                    conversationID: conversationID,
                    width: max(navBarWidth - Self.titleSideInset * 2, 0)
                )
            }
        }
        .background {
            // Measure the bar width so the centered title item can be sized to
            // (almost) fill it — the system toolbar won't honor maxWidth on a
            // principal item, so an explicit width is the only way to let the
            // avatar + name left-align inside a centered, full-width stack.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { navBarWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in navBarWidth = width }
            }
        }
        // While composing, a downward swipe should lower the keyboard — not
        // tear down the whole Send sheet.
        .interactiveDismissDisabled(isComposing)
        // Keyed on existence, not just the ID: a matched contact's chat ID is
        // pre-assigned, and fetching messages for a chat the server hasn't
        // created yet error-reports. Fires when the chat materializes.
        .task(id: chatExists ? conversationID : nil) {
            guard chatExists, let conversationID else { return }
            await conversationController.loadMessages(for: conversationID)
            if displayedMessages.isEmpty {
                displayedMessages = conversationController.messages(for: conversationID)
            }
            hasLoaded = true
            await conversationController.markRead(conversationID: conversationID)
            didInitialRead = true
        }
        .onChange(of: messages) {
            guard isTopmost else { return }
            displayedMessages = messages
        }
        .onChange(of: messages.last?.id) {
            // The initial load flips this from nil, which would double-fire
            // markRead alongside the .task above; only mark live arrivals.
            guard didInitialRead, let conversationID else { return }
            Task { await conversationController.markRead(conversationID: conversationID) }
        }
        .onAppear {
            isTopmost = true
            if hasAppeared {
                refreshChatBinding()
                syncDisplayedAfterReturn()
            } else {
                hasAppeared = true
            }
        }
        .onDisappear {
            isTopmost = false
        }
        // Keyboard fell (swipe, tap-blank, system) → bring the action buttons
        // back. Keyed off the keyboard notification, not @FocusState, which
        // doesn't reliably round-trip through interactive dismissals.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isComposerFocused = false
            isComposing = false
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func sendCash() {
        guard let contact else { return }
        guard session.hasGiveableBalance(for: ratesController.rateForBalanceCurrency()) else {
            session.dialogItem = .noGiveableBalance {
                router.navigate(to: .deposit)
            }
            return
        }
        router.push(.sendAmount(contact: contact))
    }

    private func send() {
        guard let conversationID else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        draft = ""
        isComposerFocused = true
        Task {
            await conversationController.send(text, to: conversationID)
            isSending = false
        }
    }

    /// Resigns the first responder directly via UIKit so the keyboard lowers
    /// regardless of whether @FocusState is in sync; the keyboardWillHide
    /// observer then handles the composer → buttons swap.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Plays the insertion animation for messages that landed while the amount
    /// screen covered this one. Deferred past the pop transition so the new
    /// cash card visibly springs in instead of being consumed mid-navigation.
    private func syncDisplayedAfterReturn() {
        guard displayedMessages != messages else { return }
        Task {
            try? await Task.delay(milliseconds: 400)
            guard !Task.isCancelled else { return }
            displayedMessages = messages
        }
    }

    /// After returning from the amount screen for a contact's first payment,
    /// the server has just created the chat (best-effort, so poll briefly).
    /// The event stream usually delivers the cash message on its own; this
    /// covers the gaps — a missing pre-assigned dmChatID, the stale feed (the
    /// picker's Chats section), and a missed stream event.
    private func refreshChatBinding() {
        guard case .contact = context, !chatExists else { return }
        Task {
            for attempt in 0..<3 {
                if attempt > 0 {
                    try? await Task.delay(seconds: 2)
                }
                if conversationID == nil {
                    await Task.detached { [contactSyncController] in
                        await contactSyncController.refreshMatchedSet()
                    }.value
                }
                guard let conversationID else { continue }
                await conversationController.loadFeed()
                // Done only once the FEED has the chat — messages arriving over
                // the stream flip `chatExists` early, but the picker's Recents
                // section reads the feed.
                guard conversationController.conversations.contains(where: { $0.id == conversationID }) else { continue }
                await conversationController.loadMessages(for: conversationID)
                break
            }
        }
    }
}

// MARK: - Title -

/// Avatar + name, left-aligned inside the centered principal slot (sized to
/// the measured bar width; the system toolbar won't honor maxWidth on a
/// principal item).
private struct ConversationTitleItem: View {

    let title: String
    let contact: ResolvedContact?
    let conversationID: ConversationID?
    let width: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(
                id: contact?.contactId ?? conversationID?.description ?? title,
                displayName: title,
                imageData: contact?.imageData,
                size: 44
            )
            Text(title)
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
    }
}
