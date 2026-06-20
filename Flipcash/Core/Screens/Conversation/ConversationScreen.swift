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

    /// Renders the transcript with the fully-UIKit chat instead of the SwiftUI one. Off by
    /// default; flipped from Settings ▸ Advanced (DEBUG) to compare the two on-device.
    @AppStorage("usesUIKitChat") private var usesUIKitChat = false

    @State private var hasLoaded = false
    @State private var didInitialRead = false
    @State private var isComposing = false
    @State private var hasAppeared = false
    @State private var navBarWidth: CGFloat = 0

    /// The READ watermark captured once, when the transcript first shows
    /// content. Messages past it animate the first time they're seen; at or
    /// before it they render statically. Captured (not derived) so a cold open
    /// whose feed hydrates *after* the bubbles mount can't reclassify history
    /// mid-flight and replay the amount roll. Stays `nil` only on a genuine
    /// cold first run with no read pointer yet — which renders statically,
    /// matching a warm launch.
    @State private var seenBoundary: MessageID?
    @State private var didCaptureSeenBoundary = false

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

    /// Who Send Cash pays: the synced address-book contact when there is one,
    /// otherwise a target built from the counterpart's shared phone number so a
    /// chat with a non-contact can still receive cash. `nil` only when neither a
    /// contact nor a counterpart phone number is available.
    private var sendTarget: ResolvedContact? {
        if let contact {
            return contact
        }
        guard let conversationID,
              let counterpart = conversationController.conversation(withID: conversationID)?
                .counterpart(excluding: conversationController.selfUserID) else {
            return nil
        }
        return ResolvedContact(counterpart: counterpart, dmChatID: conversationID.data)
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
            return conversationController.conversation(withID: conversationID) != nil
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

    /// The transcript's messages mapped to the UIKit chat's display items (messages + date
    /// separators). Cash branding mirrors the SwiftUI bubble: USDF reads as "Cash"; a launchpad
    /// currency uses its cached name + icon.
    private var mappedItems: [ChatItem] {
        ChatItem.from(
            messages,
            selfUserID: conversationController.selfUserID,
            counterpartRead: counterpartRead.map { (pointer: $0.pointer, date: $0.date) },
            cashBranding: { fiat in
                guard fiat.mint != .usdf, let balance = session.balance(for: fiat.mint) else { return ("Cash", nil) }
                return (balance.name, balance.imageURL)
            }
        )
    }

    /// Whether an older page is currently being fetched, so the transcript can
    /// show its loading spinner only during the fetch.
    private var isLoadingOlderMessages: Bool {
        guard let conversationID else { return false }
        return conversationController.isLoadingOlderMessages(for: conversationID)
    }

    /// The counterpart's read watermark + time, read live from the observable
    /// controller (not captured like `seenBoundary`) so the receipt updates the
    /// moment they read.
    private var counterpartRead: ReadReceiptState? {
        guard let conversationID else { return nil }
        return conversationController.conversation(withID: conversationID)?
            .counterpartReadReceipt(excluding: conversationController.selfUserID)
    }

    /// Latch the READ watermark the first time the transcript has content, so
    /// it's fixed before any cash bubble mounts.
    private func captureSeenBoundaryIfNeeded() {
        guard !didCaptureSeenBoundary, let conversationID, !messages.isEmpty else { return }
        seenBoundary = conversationController.conversation(withID: conversationID)?
            .selfReadPointer(for: conversationController.selfUserID)
        didCaptureSeenBoundary = true
    }

    var body: some View {
        Group {
            if usesUIKitChat {
                // The UIKit transcript hosts the bar internally and owns all keyboard handling,
                // so there's no SwiftUI `.safeAreaInset` bar here.
                ChatScreenRepresentable(
                    items: mappedItems,
                    onReachTop: loadOlderMessages,
                    showsSendCash: sendTarget != nil,
                    showsSendMessage: chatExists,
                    isComposing: $isComposing,
                    conversationID: conversationID,
                    onSendCash: sendCash,
                    conversationController: conversationController
                )
                .ignoresSafeArea(.keyboard)
            } else {
                Group {
                    if chatExists && !hasLoaded && messages.isEmpty {
                        LoadingView(color: .textMain)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ConversationTranscript(
                            messages: messages,
                            selfUserID: conversationController.selfUserID,
                            seenBoundary: seenBoundary,
                            counterpartRead: counterpartRead,
                            isLoadingOlder: isLoadingOlderMessages,
                            onBackgroundTap: dismissKeyboard
                        )
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ConversationBottomBar(
                        showsSendCash: sendTarget != nil,
                        showsSendMessage: chatExists,
                        isComposing: $isComposing,
                        conversationID: conversationID,
                        onSendCash: sendCash
                    )
                }
            }
        }
        .background(Color.backgroundMain)
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
            captureSeenBoundaryIfNeeded()
            hasLoaded = true
            await conversationController.markRead(conversationID: conversationID)
            didInitialRead = true

            // The SwiftUI transcript can't preserve scroll offset on prepend, so it loads the
            // full history up front and stays pinned at the newest while it pages in behind. The
            // UIKit transcript preserves offset on prepend, so it pages older on demand
            // (`onReachTop → loadOlderMessages`) instead — never the whole history at once.
            if !usesUIKitChat {
                await conversationController.loadFullHistory(for: conversationID)
            }
        }
        .onChange(of: messages.last?.id) {
            // The initial load flips this from nil, which would double-fire
            // markRead alongside the .task above; only mark live arrivals.
            guard didInitialRead, let conversationID else { return }
            conversationController.scheduleMarkRead(conversationID: conversationID)
        }
        .onAppear {
            if hasAppeared {
                refreshChatBinding()
            } else {
                captureSeenBoundaryIfNeeded()
                hasAppeared = true
            }
        }
    }

    private func sendCash() {
        guard let sendTarget else { return }
        guard session.hasGiveableBalance(for: ratesController.rateForBalanceCurrency()) else {
            session.dialogItem = .noGiveableBalance {
                router.navigate(to: .deposit)
            }
            return
        }
        router.push(.sendAmount(contact: sendTarget))
    }

    /// Fetches the next older page when the UIKit transcript nears the top. Guarded so the
    /// continuously-fired signal never stacks requests or pages past the first message.
    private func loadOlderMessages() {
        guard let conversationID,
              conversationController.hasMoreOlderMessages(for: conversationID),
              !conversationController.isLoadingOlderMessages(for: conversationID) else { return }
        Task { await conversationController.loadOlderMessages(for: conversationID) }
    }

    /// Resigns the first responder directly via UIKit so the keyboard lowers
    /// regardless of whether @FocusState is in sync; the focus-change handler
    /// then collapses the composer back to the action buttons.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                guard conversationController.conversation(withID: conversationID) != nil else { continue }
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
