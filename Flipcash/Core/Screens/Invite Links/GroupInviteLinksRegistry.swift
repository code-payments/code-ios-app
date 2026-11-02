//
//  GroupInviteLinksRegistry.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.group-invite-links-registry")

/// One ``GroupInviteLinks`` per group for the whole session, so the link made when a group is
/// created, the card that shares it and Manage Invites all see the same list and the same request
/// in flight.
@MainActor
final class GroupInviteLinksRegistry {

    private let service: GroupInviteLinks.Service
    private var linksByGroup: [ConversationID: GroupInviteLinks] = [:]
    private var autoCreated: Set<ConversationID> = []

    init(service: GroupInviteLinks.Service) {
        self.service = service
    }

    func links(for conversationID: ConversationID) -> GroupInviteLinks {
        if let existing = linksByGroup[conversationID] { return existing }
        let links = GroupInviteLinks(conversationID: conversationID, service: service)
        linksByGroup[conversationID] = links
        return links
    }

    /// Whether a freshly created group gets its first link made for it: private groups only, once.
    nonisolated static func shouldAutoCreate(isPrivate: Bool, alreadyStarted: Bool) -> Bool {
        isPrivate && !alreadyStarted
    }

    /// Makes a new private group's first invite link (never expires, no use limit) without holding
    /// anything up. A failure is logged and dropped: the first share makes the link instead.
    /// - Returns: the request, for callers that want to wait on it; nil when nothing was started.
    @discardableResult
    func autoCreateFirstLink(for conversation: Conversation) -> Task<Void, Never>? {
        guard Self.shouldAutoCreate(isPrivate: conversation.isPrivate, alreadyStarted: autoCreated.contains(conversation.id)) else {
            return nil
        }
        autoCreated.insert(conversation.id)
        let links = links(for: conversation.id)
        return Task {
            do {
                try await links.createFirstLink()
            } catch {
                logger.warning("Auto-create of the first invite link failed", metadata: ["error": "\(error)"])
            }
        }
    }
}
