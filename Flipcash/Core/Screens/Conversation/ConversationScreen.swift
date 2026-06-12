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
        return contact?.displayName ?? "Flipcash User"
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
            try? await Task.sleep(for: .milliseconds(400))
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

// MARK: - Transcript -

/// A transcript entry: a date header, or a message with its position within
/// its same-sender run. Grouping never crosses a date header.
nonisolated enum ConversationTranscriptItem: Identifiable, Equatable {

    struct Position: Equatable {
        let isFromSelf: Bool
        let groupedAbove: Bool
        let groupedBelow: Bool
        let isLatestFromSelf: Bool
    }

    case separator(Date)
    case message(ConversationMessage, Position)

    var id: String {
        switch self {
        case .separator(let date): "sep-\(date.timeIntervalSince1970)"
        case .message(let message, _): "msg-\(message.id.value)"
        }
    }

    /// Inserts a date header across `gap`-sized time gaps and computes each
    /// message's grouping within its same-sender run.
    static func items(
        from messages: [ConversationMessage],
        selfUserID: UserID,
        gap: TimeInterval = 15 * 60
    ) -> [ConversationTranscriptItem] {
        let latestFromSelfID = messages.last { $0.senderID == selfUserID }?.id
        var items: [ConversationTranscriptItem] = []

        for (index, message) in messages.enumerated() {
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let isFromSelf = message.senderID == selfUserID

            let showsSeparator: Bool
            if let previous {
                showsSeparator = message.date.timeIntervalSince(previous.date) > gap
            } else {
                showsSeparator = true
            }
            if showsSeparator {
                items.append(.separator(message.date))
            }

            let groupedAbove = !showsSeparator
                && previous.map { ($0.senderID == selfUserID) == isFromSelf } == true
            let groupedBelow = next.map {
                ($0.senderID == selfUserID) == isFromSelf
                    && $0.date.timeIntervalSince(message.date) <= gap
            } == true

            items.append(.message(message, Position(
                isFromSelf: isFromSelf,
                groupedAbove: groupedAbove,
                groupedBelow: groupedBelow,
                isLatestFromSelf: message.id == latestFromSelfID
            )))
        }
        return items
    }
}

/// The scrolling transcript. `.defaultScrollAnchor(.bottom)` keeps the newest
/// message pinned natively — no scroll math, no ScrollViewReader.
private struct ConversationTranscript: View {

    let messages: [ConversationMessage]
    let selfUserID: UserID
    let onBackgroundTap: () -> Void

    /// Messages present when the transcript mounted. Bubbles inserted later
    /// (live arrivals, the cash card after a send) roll their amount in;
    /// history renders statically.
    @State private var initialMessageIDs: Set<MessageID>?

    /// New bubble scale + opacity insertion.
    private static let insertionSpring = Animation.spring(duration: 0.23, bounce: 0.27)

    /// New message sent/received — the list springs down to the newest bubble.
    private static let scrollSpring = Animation.spring(duration: 0.30, bounce: 0.12)

    /// Scroll that rides the keyboard up/down.
    private static let keyboardScrollSpring = Animation.spring(duration: 0.30, bounce: 0)

    /// Identity of the message stack; every scroll-to-bottom targets its
    /// bottom edge.
    private static let bottomAnchor = "conversation-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        switch item {
                        case .separator(let date):
                            ConversationDateSeparator(date: date)
                        case .message(let message, let position):
                            ConversationMessageRow(
                                message: message,
                                isFromSelf: position.isFromSelf,
                                groupedAbove: position.groupedAbove,
                                groupedBelow: position.groupedBelow,
                                showsDelivered: position.isLatestFromSelf,
                                animatesAmount: initialMessageIDs.map { !$0.contains(message.id) } ?? false
                            )
                            // A new bubble scales + fades in from its aligned edge.
                            .transition(
                                .scale(scale: 0.95, anchor: position.isFromSelf ? .trailing : .leading)
                                    .combined(with: .opacity)
                            )
                        }
                    }
                }
                // Every scroll-to-bottom targets the stack's bottom edge.
                .id(Self.bottomAnchor)
                .padding(.vertical, 12)
                // Tapping empty space lowers the keyboard; bubbles consume their
                // own taps (see ConversationMessageRow).
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)
                .animation(Self.insertionSpring, value: messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            // One primitive — "show the bottom" — fired at each moment it
            // should be shown. No scroll anchors: a thread too short to
            // scroll just no-ops and stays at the top.
            //
            //   • open a populated thread at the newest message. Run
            //     immediately and again after the first layout pass — onAppear
            //     can fire before the list is measured, which makes a lone
            //     scrollTo a no-op.
            .onAppear {
                if initialMessageIDs == nil {
                    initialMessageIDs = Set(messages.map(\.id))
                }
                scrollToBottom(proxy)
                DispatchQueue.main.async { scrollToBottom(proxy) }
            }
            //   • a message arrives (sent or received) → spring down to it
            .onChange(of: messages.count) {
                scrollToBottom(proxy, animation: Self.scrollSpring)
            }
            //   • keyboard rises → ride the newest message up with it
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                scrollToBottom(proxy, animation: Self.keyboardScrollSpring)
            }
            //   • keyboard falls (swipe, tap-blank, system) → keep the thread
            //     pinned down
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                scrollToBottom(proxy, animation: Self.keyboardScrollSpring)
            }
        }
    }

    /// Scrolls the newest content into view. A thread too short to scroll
    /// no-ops and stays at the top. Pass an `animation` to ease the scroll;
    /// omit for an instant jump (e.g. opening the thread).
    private func scrollToBottom(_ proxy: ScrollViewProxy, animation: Animation? = nil) {
        if let animation {
            withAnimation(animation) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    /// Kept on this child view (whose inputs exclude the composer draft) so
    /// keystrokes don't recompute it.
    private var items: [ConversationTranscriptItem] {
        ConversationTranscriptItem.items(from: messages, selfUserID: selfUserID)
    }
}

// MARK: - Bottom bar -

/// Send Cash / Send Message buttons, swapped for the message composer while
/// composing. Pinned via `.safeAreaInset`; native keyboard avoidance handles
/// the rest.
private struct ConversationBottomBar: View {

    let showsSendCash: Bool
    let showsSendMessage: Bool
    @Binding var isComposing: Bool
    @Binding var draft: String
    var focus: FocusState<Bool>.Binding
    let canSend: Bool
    let onSendCash: () -> Void
    let onSendText: () -> Void

    /// Action bar ⇄ composer swap — the button group springs in/out (scaling
    /// from 95%) while the composer fades.
    private static let swapSpring = Animation.spring(duration: 0.27, bounce: 0.31)

    var body: some View {
        ZStack {
            if isComposing {
                ConversationComposer(draft: $draft, focus: focus, canSend: canSend, onSend: onSendText)
                    .transition(.opacity)
            } else {
                ConversationActionBar(
                    showsSendCash: showsSendCash,
                    showsSendMessage: showsSendMessage,
                    onSendCash: onSendCash,
                    onSendMessage: { isComposing = true }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(Self.swapSpring, value: isComposing)
        .animation(Self.swapSpring, value: showsSendMessage)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                gradient: Gradient(colors: [Color.backgroundMain, Color.backgroundMain, .clear]),
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea()
        }
    }
}

/// Send Cash alone until the chat exists, then Send Cash + Send Message.
private struct ConversationActionBar: View {

    let showsSendCash: Bool
    let showsSendMessage: Bool
    let onSendCash: () -> Void
    let onSendMessage: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if showsSendCash {
                Button("Send Cash", action: onSendCash)
                    .buttonStyle(.filled)
            }
            if showsSendMessage {
                // Material-only frosted button (no fill) — matches the .filled
                // metrics (full width, 60pt tall, 6pt radius, appTextMedium).
                Button(action: onSendMessage) {
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
    }
}

// MARK: - Composer -

/// The glass type box: a multiline field with a send button that appears once
/// there's text. Swiping the chat down lowers the keyboard and the box.
private struct ConversationComposer: View {

    @Binding var draft: String
    var focus: FocusState<Bool>.Binding
    let canSend: Bool
    let onSend: () -> Void

    /// Send button scale-in/out as text appears/clears.
    private static let sendButtonSpring = Animation.spring(duration: 0.17, bounce: 0.34)

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .font(.appTextMessage)
                .foregroundStyle(Color.textMain)
                .tint(.white)
                .lineLimit(1...5)
                .focused(focus)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 34)

            if canSend {
                Button(action: onSend) {
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
        .animation(Self.sendButtonSpring, value: canSend)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .modifier(ComposerGlass())
        .padding(.horizontal, 12)
        // Focus must be requested after the field joins the hierarchy; setting
        // it in the Send Message tap (same transaction) can silently fail.
        .onAppear { focus.wrappedValue = true }
    }
}

/// Liquid-glass background on iOS 26; ultra-thin material below.
private struct ComposerGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        } else {
            content.background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        }
    }
}
