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
    /// Multi-select mode and its picks.
    public private(set) var selection = ChatListSelectionMode<ID>()

    public init() {}

    /// Multi-select mode is on.
    public var isSelecting: Bool { selection.isActive }
    /// The picked chats while ``isSelecting``.
    public var selected: Set<ID> { selection.selected }

    /// The list hasn't loaded yet.
    public var isLoading: Bool { projection == nil }

    /// A selected filter keeps the chips in view: they explain the list.
    public var showsChips: Bool { chipsRevealed || filter != .all }

    /// The rows the current filter shows, in order.
    public var visibleIDs: [ID] {
        projection.map(visibleIDs(in:)) ?? []
    }

    /// The Archived row shows, on the All filter only.
    public var showsArchivedRow: Bool {
        projection.map(showsArchivedRow(in:)) ?? false
    }

    /// No chats at all, archived included: the empty state shows.
    public var hasNoChatsAtAll: Bool {
        projection.map(Self.hasNoChatsAtAll(in:)) ?? false
    }

    // The same rules over a projection the caller holds. The screen reads the controller's live
    // projection each body pass, so it asks these rather than the stored copy.

    /// The rows the current filter shows in `projection`, in order.
    public func visibleIDs(in projection: ChatListProjection<ID>) -> [ID] {
        filter.ids(in: projection)
    }

    /// The Archived row shows in `projection`, on the All filter only.
    public func showsArchivedRow(in projection: ChatListProjection<ID>) -> Bool {
        filter == .all && projection.archivedRowVisible
    }

    /// `projection` has no chats at all, archived included.
    public static func hasNoChatsAtAll(in projection: ChatListProjection<ID>) -> Bool {
        projection.main.isEmpty && !projection.archivedRowVisible
    }

    /// Takes a new projection and drops picks no longer listed, so an archived or left chat isn't
    /// acted on.
    public mutating func update(_ projection: ChatListProjection<ID>) {
        self.projection = projection
        selection.retain(Set(projection.main))
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
        selection.begin()
    }

    /// Picks or unpicks one chat.
    public mutating func toggle(_ id: ID) {
        selection.toggle(id)
    }

    /// Leaves select mode.
    public mutating func endSelection() {
        selection.end()
    }

    // MARK: - Leaving the list

    /// The chat a row opens.
    public func openChat(_ id: ID) -> ChatsDestination<ID> { .chat(id) }

    /// The Archived row's screen.
    public func openArchived() -> ChatsDestination<ID> { .archived }

    /// The compose button's screen.
    public func openNewChat() -> ChatsDestination<ID> { .newChat }
}

/// Where the Chats list sends the user. The screen maps each case to the app's router, so the
/// shared behavior tests check the choice without the app target.
public enum ChatsDestination<ID: Hashable & Sendable>: Hashable, Sendable {
    case chat(ID)
    case archived
    case newChat
}

/// The Chats list's select mode: whether it is on, and which chats are picked. ``ChatsModel`` holds
/// one, and so does the app's `ChatSelection`, which the tab view owns so it can swap the tab bar
/// for the select actions.
public struct ChatListSelectionMode<ID: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var isActive = false
    public private(set) var selected: Set<ID> = []

    public init() {}

    /// Enters select mode with nothing selected.
    public mutating func begin() {
        selected = []
        isActive = true
    }

    /// Leaves select mode.
    public mutating func end() {
        isActive = false
        selected = []
    }

    /// Picks or unpicks one chat.
    public mutating func toggle(_ id: ID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    /// Drops picks that are no longer in `ids`, so an archived or left chat isn't acted on.
    public mutating func retain(_ ids: Set<ID>) {
        let kept = selected.intersection(ids)
        if kept != selected { selected = kept }
    }
}
