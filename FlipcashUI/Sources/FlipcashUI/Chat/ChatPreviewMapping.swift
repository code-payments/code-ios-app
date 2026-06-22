//
//  ChatPreviewMapping.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import FlipcashCore
import Foundation

extension ChatItem {

    /// Maps a flat list of `ConversationMessage` values to the last `limit` chat rows, sorted
    /// chronologically (oldest first). Intended for notification content-extension previews and
    /// other contexts that can link `FlipcashUI` but not the main app target.
    ///
    /// - Parameters:
    ///   - messages: The full or partial list of conversation messages in any order.
    ///   - selfUserID: The current user's ID; messages whose `senderID` matches are rendered on
    ///     the `.me` side.
    ///   - limit: Maximum number of rows to return. Defaults to 3. The *most recent* messages
    ///     (by `MessageID`) are kept, presented oldest-first.
    public static func preview(
        from messages: [ConversationMessage],
        selfUserID: UserID,
        limit: Int = 3
    ) -> [ChatItem] {
        let sorted = messages.sorted { $0.id < $1.id }
        let slice = sorted.suffix(limit)

        return slice.map { message in
            let sender: ChatMessage.Sender = message.senderID == selfUserID ? .me : .other

            let content: ChatMessage.Content
            switch message.content {
            case .text(let text):
                content = .text(text)
            case .cash(let fiat):
                content = .cash(ChatCashContent(
                    amount: fiat.nativeAmount.formatted(),
                    token: "Cash"
                ))
            }

            return .message(ChatMessage(
                id: String(message.id.value),
                content: content,
                sender: sender,
                isContinuationFromPrevious: false,
                isContinuedByNext: false
            ))
        }
    }
}
