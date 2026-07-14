//
//  MessageLoader.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// A per-conversation, bounded window over a conversation's messages, read from the local database.
/// It renders only a recent slice so a fresh open lays out a window rather than the whole thread;
/// `loadOlder()` grows the window over already-persisted history and pages the next older batch from
/// the server (which persists it) once the local history is exhausted.
@MainActor @Observable
final class MessageLoader {

    private let conversationID: ConversationID
    private let controller: ConversationController

    /// How many newest confirmed messages the window currently reveals; grows as the reader pages back.
    private var windowLimit = MessageLoader.initialWindow

    init(conversationID: ConversationID, controller: ConversationController) {
        self.conversationID = conversationID
        self.controller = controller
    }

    /// The bounded slice actually rendered: the newest `windowLimit` confirmed messages (from the DB)
    /// with the optimistic overlay applied.
    var messages: [ConversationMessage] {
        controller.windowedMessages(for: conversationID, limit: windowLimit)
    }

    /// Reveals an older step: grows the window over already-persisted history, or pages the next older
    /// batch from the server (which persists it) once the local history is exhausted.
    func loadOlder() {
        let available = controller.confirmedMessageCount(for: conversationID)
        if windowLimit < available {
            windowLimit = min(windowLimit + Self.step, available)
        } else {
            fetchOlder()
        }
    }

    private func fetchOlder() {
        Task {
            await controller.loadOlderMessages(for: conversationID)
            let available = controller.confirmedMessageCount(for: conversationID)
            if available > windowLimit {
                windowLimit = min(windowLimit + Self.step, available)
            }
        }
    }

    private static let initialWindow = 60
    private static let step = 40
}
