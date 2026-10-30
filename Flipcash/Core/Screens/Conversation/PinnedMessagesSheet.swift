//
//  PinnedMessagesSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What the pinned list was opened for.
struct PinnedMessagesRequest: Identifiable {
    let id = UUID()
    /// The message waiting to be pinned once the viewer unpins one, when the chat was at the cap.
    let waiting: ConversationMessage?
}

/// The pinned list's presentation from the chat: whether it's open, the message a row asked to
/// jump to, which waits until the sheet has closed, and the photo resolver its rows share.
@MainActor
@Observable
final class PinnedMessagesPresentation {
    var request: PinnedMessagesRequest?
    /// The message a tapped row asked for, landed on once the sheet has gone.
    var pendingJump: MessageID?
    /// Holds the keyboard down while the list opens: a long-press menu hands the composer its
    /// focus back as it closes, which would raise the keyboard over the sheet.
    @ObservationIgnored let keyboard = KeyboardSuppressor()
    /// The latest photo URL minter, read by ``mediaURLResolver`` at fetch time.
    @ObservationIgnored var mintMediaURL: (BlobID) async throws -> URL? = { _ in nil }
    /// The latest photo decrypter, read by ``mediaURLResolver``.
    @ObservationIgnored var mediaBlobDecrypt: () async -> ChatMediaURLResolver.BlobDecrypt? = { nil }
    /// The photo resolver the rows share for the visit.
    @ObservationIgnored lazy var mediaURLResolver = ChatMediaURLResolver(
        fetch: { [weak self] blobID in
            guard let self else { return nil }
            return try await self.mintMediaURL(blobID)
        },
        decrypt: { [weak self] in
            await self?.mediaBlobDecrypt()
        }
    )

    /// Hands back the message to land on, once.
    func takePendingJump() -> MessageID? {
        defer { pendingJump = nil }
        return pendingJump
    }
}

/// Every pin the viewer can see, newest first, each drawn as its transcript row with who pinned it
/// and when. Unpin shows when the viewer can pin. Opened at the cap, it pins the waiting message
/// once an unpin frees a slot.
struct PinnedMessagesSheet: View {

    let conversationID: ConversationID
    let pins: ConversationPins
    let canPin: Bool
    let selfUserID: UserID
    /// The waiting message's one line, for the header asking for an unpin.
    let waitingSnippet: String?
    let waiting: ConversationMessage?
    let row: (ConversationMessage) -> ChatMessage?
    let name: (UserID) -> String
    let avatarData: [UserID: Data]
    let linkCardSource: any LinkCardSource
    let mediaURLResolver: ChatMediaURLResolver
    let onSelect: (MessageID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var busy: Set<MessageID> = []
    @State private var error: String?
    /// Whether the waiting message still waits: false once it pins.
    @State private var isWaiting = true
    /// Opens tall when asking for an unpin, so the whole list shows under the notice.
    @State private var detent: PresentationDetent = .medium
    /// The rows last drawn, kept on screen while the sheet closes after its last unpin.
    @State private var lastRows: [ConversationPin] = []

    var body: some View {
        let visible = pins.visible(in: conversationID)
        let rows = visible.isEmpty ? lastRows : visible
        ScrollView {
            VStack(spacing: 12) {
                Text("Pinned Messages")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                if let waitingSnippet, waiting != nil, isWaiting {
                    Text("Pinned messages are full. Unpin one to pin \"\(waitingSnippet)\"")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, ChatColumnCell.rowInset)
                }
                if let error {
                    Text(error)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, ChatColumnCell.rowInset)
                }
                VStack(spacing: 16) {
                    ForEach(rows, id: \.messageID) { pin in
                        if let message = pin.message, let chatMessage = row(message) {
                            item(pin, chatMessage)
                        }
                    }
                }
                .animation(.default, value: rows.map(\.messageID))
            }
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.backgroundMain)
        .presentationDetents([.medium, .large], selection: $detent)
        .onAppear { if waiting != nil { detent = .large } }
        .presentationDragIndicator(.visible)
        // The system's glass lights up wherever it's touched at the medium detent.
        .presentationBackground(Color.backgroundMain)
        .onChange(of: visible, initial: true) { _, visible in
            if !visible.isEmpty { lastRows = visible }
        }
        .onChange(of: visible.isEmpty) { _, isEmpty in
            if isEmpty, waiting == nil || !isWaiting { dismiss() }
        }
        .onDisappear {
            if pins.pendingPin?.conversationID == conversationID { pins.cancelPendingPin() }
        }
    }


    /// "Pinned by <name> · <date>", leaving out whichever the server didn't send.
    private func pinnedLine(_ pin: ConversationPin) -> String {
        var line = pin.pinnedBy.map { "Pinned by \(name($0))" } ?? "Pinned"
        if let pinnedAt = pin.pinnedAt {
            line += " · \(pinnedAt.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return line
    }
    private func item(_ pin: ConversationPin, _ message: ChatMessage) -> some View {
        let isMine = message.sender == .me
        // Under the bubble's edge: the transcript's row inset, past the avatar gutter in a group.
        let inset = ChatColumnCell.rowInset + (message.isAttributedTranscript && !isMine ? ChatColumnCell.authorGutterWidth : 0)
        return VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            Button {
                dismiss()
                onSelect(pin.messageID)
            } label: {
                ChatMessageCellView(
                    message: message,
                    authorImageData: message.author.flatMap { avatarData[$0.id] },
                    linkCardSource: linkCardSource,
                    mediaURLResolver: mediaURLResolver
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the message in the chat")

            HStack(spacing: 6) {
                Text(pinnedLine(pin))
                    .foregroundStyle(Color.textSecondary)
                if canPin {
                    Button {
                        unpin(pin.messageID)
                    } label: {
                        Text("Unpin")
                            .foregroundStyle(Color.textMain)
                            // A 44pt target around the caption, without moving the line.
                            .padding(.vertical, 14)
                            .padding(.horizontal, 10)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -14)
                    .padding(.horizontal, -10)
                    .disabled(busy.contains(pin.messageID))
                }
            }
            .font(.appTextCaption)
            .padding(isMine ? .trailing : .leading, inset)
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    private func unpin(_ messageID: MessageID) {
        busy.insert(messageID)
        error = nil
        Task {
            defer { busy.remove(messageID) }
            guard await pins.unpin(messageID, in: conversationID) else {
                error = "Couldn't unpin that message. Please try again."
                return
            }
            guard let waiting, isWaiting else { return }
            switch await pins.pin(waiting, in: conversationID) {
            case .pinned:
                isWaiting = false
                dismiss()
            case .full:
                error = "Pinned messages are still full. Unpin another to pin this one."
            case .failed:
                error = "Couldn't pin the message. Please try again."
            }
        }
    }
}

extension ChatMessage {

    /// The row as the pinned list draws it: attributed to `author` on the leading side whoever sent
    /// it, without the receipt, reactions or grouping it has in the transcript.
    func pinnedListRow(author: ChatAuthor) -> ChatMessage {
        ChatMessage(
            id: id,
            serverID: serverID,
            content: content,
            sender: .other,
            isEmojiOnly: isEmojiOnly,
            linkPreview: linkPreview,
            isEdited: isEdited,
            quote: quote,
            author: author,
            isAttributedTranscript: true,
            part: part,
            // Whether the viewer may see the photo's bytes, not a reaction affordance here.
            canReact: canReact,
            sentAt: sentAt
        )
    }
}
