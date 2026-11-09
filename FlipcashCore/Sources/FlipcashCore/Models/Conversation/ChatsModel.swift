//
//  ChatsModel.swift
//  FlipcashCore
//

import Foundation

/// The Chats tab's screen state: the selected filter, whether the chips are in view, and select mode,
/// over the projection the controller hands it. Each action is a plain mutation, so the same rules
/// run in the screen and in the shared behavior tests.
public struct ChatsModel<ID: Hashable & Sendable>: Sendable {

    /// The rows, chips, Archived row and badge, from ``ChatListProjection/project(_:)``. `nil` until
    /// the feed has resolved.
    public private(set) var projection: ChatListProjection<ID>?
    /// The selected chip.
    public private(set) var filter: ChatListFilter = .all
    /// Set by a pull down that starts at the top of the list.
    public private(set) var chipsRevealed = false
    /// Multi-select mode.
    public private(set) var isSelecting = false
    /// The picked chats while ``isSelecting``.
    public private(set) var selected: Set<ID> = []

    public init() {}

    /// The list hasn't loaded yet.
    public var isLoading: Bool { projection == nil }

    /// A selected filter keeps the chips in view: they explain the list.
    public var showsChips: Bool { chipsRevealed || filter != .all }

    /// The rows the current filter shows, in order.
    public var visibleIDs: [ID] {
        projection.map { filter.ids(in: $0) } ?? []
    }

    /// The Archived row shows, on the All filter only.
    public var showsArchivedRow: Bool {
        filter == .all && (projection?.archivedRowVisible ?? false)
    }

    /// No chats at all, archived included: the empty state shows.
    public var hasNoChatsAtAll: Bool {
        guard let projection else { return false }
        return projection.main.isEmpty && !projection.archivedRowVisible
    }

    /// Takes a new projection and drops picks no longer listed, so an archived or left chat isn't
    /// acted on.
    public mutating func update(_ projection: ChatListProjection<ID>) {
        self.projection = projection
        let kept = selected.intersection(projection.main)
        if kept != selected { selected = kept }
    }

    /// Selects a chip.
    public mutating func select(_ filter: ChatListFilter) {
        self.filter = filter
    }

    /// Pulls the chips into view.
    public mutating func revealChips() {
        chipsRevealed = true
    }

    /// Enters select mode with nothing selected.
    public mutating func beginSelection() {
        selected = []
        isSelecting = true
    }

    /// Picks or unpicks one chat.
    public mutating func toggle(_ id: ID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    /// Leaves select mode.
    public mutating func endSelection() {
        isSelecting = false
        selected = []
    }
}
