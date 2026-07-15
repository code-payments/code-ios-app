//
//  ConversationLoadCoordinator.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import FlipcashUI

/// Owns a conversation's `MessageLoader` and turns its window into display-ready `[ChatItem]`.
/// It observes exactly the inputs the mapping consumes, maps them off the main thread, and lands
/// the result as immutable `items`; the view reads only `items`, never raw messages. An unrelated
/// observable tick (a typing heartbeat, another conversation's event) leaves the inputs unchanged
/// and does no work.
@MainActor @Observable
final class ConversationLoadCoordinator {

    let loader: MessageLoader

    /// The rendered transcript, produced off the main thread and landed here as immutable state.
    private(set) var items: [ChatItem] = []

    let conversationID: ConversationID
    private let controller: ConversationController
    private let session: Session

    @ObservationIgnored private var lastInputs: Inputs?
    @ObservationIgnored private var mapTask: Task<Void, Never>?

    init(conversationID: ConversationID, controller: ConversationController, session: Session) {
        self.conversationID = conversationID
        self.controller = controller
        self.session = session
        self.loader = MessageLoader(conversationID: conversationID, controller: controller)

        // First paint is synchronous so an open never flashes an empty transcript; every later
        // change maps off the main thread.
        let initial = currentInputs()
        self.lastInputs = initial
        self.items = Self.map(initial)
        observeInputs()
    }

    /// The reader reached the top — reveal older history.
    func reachedTop() { loader.loadOlder() }

    // Tracks exactly the inputs `map` reads; on the next change to any of them it re-maps off the
    // main thread and re-arms. An unchanged input set short-circuits before spawning any work.
    private func observeInputs() {
        let inputs = withObservationTracking {
            currentInputs()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeInputs() }
        }
        guard inputs != lastInputs else { return }
        lastInputs = inputs
        mapTask?.cancel()
        mapTask = Task { [weak self] in
            let mapped = await Task.detached { Self.map(inputs) }.value
            guard let self, !Task.isCancelled else { return }
            self.items = mapped
        }
    }

    private func currentInputs() -> Inputs {
        let read = controller.conversation(withID: conversationID)?
            .counterpartReadReceipt(excluding: controller.selfUserID)
        let window = loader.messages
        var branding: [PublicKey: Inputs.Branding] = [:]
        for message in window {
            guard case .cash(let fiat) = message.content, branding[fiat.mint] == nil else { continue }
            if let balance = session.balance(for: fiat.mint) {
                branding[fiat.mint] = .init(token: balance.name, iconURL: balance.imageURL)
            }
        }
        return Inputs(
            messages: window,
            selfUserID: controller.selfUserID,
            counterpartPointer: read?.pointer,
            counterpartReadDate: read?.date,
            suppressReceiptFor: controller.settlingSendID,
            isTyping: controller.isCounterpartTyping(in: conversationID),
            branding: branding
        )
    }

    nonisolated private static func map(_ inputs: Inputs) -> [ChatItem] {
        var items = ChatItem.from(
            inputs.messages,
            selfUserID: inputs.selfUserID,
            counterpartRead: inputs.counterpartPointer.map { (pointer: $0, date: inputs.counterpartReadDate) },
            suppressReceiptFor: inputs.suppressReceiptFor,
            cashBranding: { fiat in
                guard let branding = inputs.branding[fiat.mint] else { return ("Cash", nil) }
                return (branding.token, branding.iconURL)
            }
        )
        if inputs.isTyping {
            items.append(.typingIndicator)
        }
        return items
    }

    /// Everything `map` reads, captured by value so an unchanged set short-circuits the remap and
    /// the snapshot can cross to a background task. Cash branding is pre-resolved per mint so a
    /// branding change participates.
    struct Inputs: Equatable, Sendable {
        var messages: [ConversationMessage]
        var selfUserID: UserID
        var counterpartPointer: MessageID?
        var counterpartReadDate: Date?
        var suppressReceiptFor: String?
        var isTyping: Bool
        var branding: [PublicKey: Branding]

        struct Branding: Equatable, Sendable {
            var token: String
            var iconURL: URL?
        }
    }
}
