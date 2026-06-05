//
//  ChatScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A DM conversation: an iMessage-style transcript + composer. Reads live
/// messages from `ChatController`, which owns the single event stream.
struct ChatScreen: View {

    let chatID: ChatID

    @Environment(ChatController.self) private var chatController

    @State private var draft = ""
    @State private var isSending = false
    @State private var hasLoaded = false
    @FocusState private var isComposerFocused: Bool

    private var messages: [ChatMessage] {
        chatController.messages(for: chatID)
    }

    var body: some View {
        Group {
            if messages.isEmpty {
                if hasLoaded {
                    ContentUnavailableView(
                        "No messages yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Say hello to start the conversation.")
                    )
                } else {
                    LoadingView(color: .textMain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ConversationTranscript(messages: messages, selfUserID: chatController.selfUserID)
            }
        }
        .background(Color.backgroundMain)
        .safeAreaInset(edge: .bottom) {
            ChatComposer(draft: $draft, focus: $isComposerFocused, canSend: canSend, onSend: send)
        }
        .navigationTitle(chatController.displayName(forChatID: chatID))
        .toolbarTitleDisplayMode(.inline)
        .task {
            await chatController.loadMessages(for: chatID)
            hasLoaded = true
            await chatController.markRead(chatID: chatID)
        }
        .onChange(of: messages.last?.id) {
            Task { await chatController.markRead(chatID: chatID) }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        draft = ""
        isComposerFocused = true
        Task {
            await chatController.send(text, to: chatID)
            isSending = false
        }
    }
}

/// A transcript entry: either a date header or a message bubble with its
/// run-position flags.
private enum TranscriptItem: Identifiable {
    case separator(Date)
    case message(ChatMessage, isFromSelf: Bool, startsRun: Bool, endsRun: Bool)

    var id: String {
        switch self {
        case .separator(let date): "sep-\(date.timeIntervalSince1970)"
        case .message(let message, _, _, _): "msg-\(message.id.value)"
        }
    }
}

/// The scrolling transcript. `.defaultScrollAnchor(.bottom)` keeps the newest
/// message pinned natively — no scroll math, no ScrollViewReader.
private struct ConversationTranscript: View {

    let messages: [ChatMessage]
    let selfUserID: UserID

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(items) { item in
                    switch item {
                    case .separator(let date):
                        ConversationDateSeparator(date: date)
                    case .message(let message, let isFromSelf, let startsRun, let endsRun):
                        ConversationMessageRow(
                            message: message,
                            isFromSelf: isFromSelf,
                            showsTimestamp: endsRun
                        )
                        .id(message.id)
                        .padding(.top, startsRun ? 6 : 0)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
    }

    /// Groups messages into same-sender runs and inserts date headers across time
    /// gaps. Kept on this child view (whose inputs exclude the composer draft) so
    /// keystrokes don't recompute it.
    private var items: [TranscriptItem] {
        let gap: TimeInterval = 15 * 60
        var items: [TranscriptItem] = []

        for (index, message) in messages.enumerated() {
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let isFromSelf = message.senderID == selfUserID

            let startsRun = previous == nil
                || (previous!.senderID == selfUserID) != isFromSelf
                || message.date.timeIntervalSince(previous!.date) > gap

            if startsRun {
                items.append(.separator(message.date))
            }

            let endsRun = next == nil
                || (next!.senderID == selfUserID) != isFromSelf
                || next!.date.timeIntervalSince(message.date) > gap

            items.append(.message(message, isFromSelf: isFromSelf, startsRun: startsRun, endsRun: endsRun))
        }
        return items
    }
}

/// The bottom composer. Pinned via `.safeAreaInset`; native keyboard avoidance
/// handles the rest — no keyboard observers.
private struct ChatComposer: View {

    @Binding var draft: String
    var focus: FocusState<Bool>.Binding
    let canSend: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            InputContainer {
                TextField("Message", text: $draft, axis: .vertical)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1...5)
                    .focused(focus)
            }
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.textMain : Color.textSecondary)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.backgroundMain)
    }
}
