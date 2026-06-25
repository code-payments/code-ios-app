//
//  ChatSpotlightIndexer.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import CoreSpotlight
import FlipcashCore
import FlipcashUI

nonisolated private let logger = Logger(label: "flipcash.spotlight")

/// Mirrors `ConversationController.conversations` into the on-device Spotlight
/// index so DM chats are searchable and open on tap. Session-scoped: a sibling
/// of `ConversationController` on `SessionContainer`, started after the feed
/// hydrates and torn down on logout.
///
/// Observes the feed via a re-arming `withObservationTracking` loop, debounced
/// so a burst of stream events collapses into one reindex.
@MainActor
final class ChatSpotlightIndexer {

    private let controller: ConversationController
    private let contactSyncController: ContactSyncController
    private let index: CSSearchableIndex

    private var debounce: Task<Void, Never>?
    /// Identifiers currently in the index, so a reindex can delete the ones
    /// that dropped out of the feed without clearing the whole domain.
    private var indexedIdentifiers: Set<String> = []
    /// Rendered avatar PNGs keyed by `id|displayName|imageBytes`, so reindexes
    /// reuse unchanged avatars instead of re-rasterizing on the main actor.
    private var avatarCache: [String: Data] = [:]

    init(
        controller: ConversationController,
        contactSyncController: ContactSyncController,
        index: CSSearchableIndex = .default()
    ) {
        self.controller = controller
        self.contactSyncController = contactSyncController
        self.index = index
    }

    /// Indexes the current feed and arms observation. Idempotent enough for the
    /// single call site, but observation re-arms itself on every change.
    func start() {
        observe()
    }

    /// Clears every chat item from the index — called on logout so one user's
    /// conversations never surface under another account.
    func stop() {
        debounce?.cancel()
        debounce = nil
        indexedIdentifiers = []
        avatarCache = [:]
        index.deleteSearchableItems(withDomainIdentifiers: [ChatSpotlightItem.domainIdentifier]) { error in
            if let error {
                logger.error("Failed to clear chat Spotlight index", metadata: ["error": "\(error)"])
            }
        }
    }

    private func observe() {
        // Read every observable the items depend on — the feed *and* the
        // resolved contact directory (`displayName(for:)` reads it) — so a
        // change re-arms and reindexes. Contact sync resolves names and photos
        // after launch; tracking only the feed would leave a chat indexed under
        // its phone-number fallback with no avatar. No image rendering here —
        // that's reindex()'s job, off the debounce.
        _ = withObservationTracking {
            controller.conversations.map { controller.displayName(for: $0) }
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleReindex()
                self.observe()
            }
        }
        scheduleReindex()
    }

    private func scheduleReindex() {
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.reindex()
        }
    }

    private func reindex() {
        let items = controller.conversations.map { conversation -> ChatSpotlightItem in
            let contact = counterpartContact(for: conversation)
            let displayName = controller.displayName(for: conversation)
            return ChatSpotlightItem(
                conversation: conversation,
                displayName: displayName,
                counterpartPhoneE164: conversation.counterpart(excluding: controller.selfUserID)?.phoneE164,
                thumbnailData: avatar(
                    forID: contact?.contactId ?? conversation.id.description,
                    displayName: displayName,
                    imageData: contact?.imageData
                )
            )
        }
        let currentIdentifiers = Set(items.map(\.uniqueIdentifier))
        let removed = indexedIdentifiers.subtracting(currentIdentifiers)
        indexedIdentifiers = currentIdentifiers

        index.indexSearchableItems(items.map(\.searchableItem)) { error in
            if let error {
                logger.error("Failed to index chats in Spotlight", metadata: ["error": "\(error)"])
            } else {
                logger.info("Indexed chats in Spotlight", metadata: ["count": "\(items.count)"])
            }
        }

        guard !removed.isEmpty else { return }
        index.deleteSearchableItems(withIdentifiers: Array(removed)) { error in
            if let error {
                logger.error("Failed to remove stale chats from Spotlight", metadata: ["error": "\(error)"])
            }
        }
    }

    /// The synced contact behind a DM, matched on the pre-assigned chat id —
    /// the source of the counterpart's photo (nil for an unsaved number).
    private func counterpartContact(for conversation: Conversation) -> ResolvedContact? {
        contactSyncController.resolvedContacts.onFlipcash.first { $0.dmChatID == conversation.id.data }
    }

    /// Cached avatar PNG, keyed by the inputs that affect the image. Most
    /// reindexes fire for an unrelated change (a new last message), where no
    /// avatar changed — the cache returns the existing PNG instead of
    /// re-rasterizing every conversation's avatar on the main actor.
    private func avatar(forID id: String, displayName: String, imageData: Data?) -> Data? {
        let key = "\(id)|\(displayName)|\(imageData?.count ?? 0)"
        if let cached = avatarCache[key] { return cached }
        let rendered = renderAvatar(id: id, displayName: displayName, imageData: imageData)
        avatarCache[key] = rendered
        return rendered
    }

    /// Renders the app's own avatar (contact photo, or initials/person
    /// monogram) to PNG for the Spotlight thumbnail, so results match the
    /// in-app avatar instead of falling back to a bare app icon.
    ///
    /// Rendered at the avatar's canonical 44pt size: its monogram font is tuned
    /// for that, so a larger frame would shrink the initials to a tiny fraction
    /// of the circle. The color scheme is pinned to `.dark` (the app's only
    /// scheme) so the asset colors resolve the way the avatar was designed,
    /// rather than the renderer's default light variant. `scale = 3` matches the
    /// highest real device scale (Spotlight's slot is system-fixed, not ours).
    private func renderAvatar(id: String, displayName: String, imageData: Data?) -> Data? {
        let renderer = ImageRenderer(
            content: ContactAvatarView(id: id, displayName: displayName, imageData: imageData, size: 44)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }
}
