//
//  MessageLoader.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// A per-conversation, bounded window over a conversation's messages. It renders only a recent
/// slice so a fresh open lays out a window rather than the whole thread; `loadOlder()` grows it
/// and pages from the server once the loaded set is exhausted. The window is anchored by message
/// id, so an arriving message never drops the oldest shown row out from under a reader who has
/// scrolled up.
@MainActor @Observable
final class MessageLoader {

    private let conversationID: ConversationID
    private let controller: ConversationController

    /// The oldest message id currently shown; `nil` renders the most recent `initialWindow`.
    private var startID: MessageID?

    init(conversationID: ConversationID, controller: ConversationController) {
        self.conversationID = conversationID
        self.controller = controller
    }

    /// The bounded slice actually rendered.
    var messages: [ConversationMessage] {
        let all = controller.messages(for: conversationID)
        guard let startID, let start = all.firstIndex(where: { $0.id >= startID }) else {
            return Array(all.suffix(Self.initialWindow))
        }
        return Array(all[start...])
    }

    /// Reveals an older step of the loaded history, paging from the server once the window
    /// reaches the oldest loaded message.
    func loadOlder() {
        let all = controller.messages(for: conversationID)
        guard let oldest = messages.first,
              let index = all.firstIndex(where: { $0.id == oldest.id }) else {
            fetchOlder()
            return
        }
        if index == 0 {
            fetchOlder()
        } else {
            startID = all[max(0, index - Self.step)].id
        }
    }

    private func fetchOlder() {
        Task { await controller.loadOlderMessages(for: conversationID) }
    }

    private static let initialWindow = 60
    private static let step = 40
}
