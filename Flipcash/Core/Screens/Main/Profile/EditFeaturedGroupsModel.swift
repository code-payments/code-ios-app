//
//  EditFeaturedGroupsModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.edit-featured-groups")

/// The favorite-groups picker's choices, ordered selection and its one save.
///
/// The calls are injected: `FlipClient` is a concrete class with a live gRPC channel, so a test
/// has nothing to fake.
@MainActor
@Observable
final class EditFeaturedGroupsModel {

    /// Where the save is. `.saved` is held by the screen for its checkmark before it pops.
    enum SaveState: Equatable {
        case normal
        case saving
        case saved
    }

    /// Where the candidate list is.
    enum LoadState: Equatable {
        case loading
        case loaded
        /// The featured list could not be read, so a save could drop groups the screen never saw.
        case failed
    }

    /// Why a save failed, for the dialog.
    enum Failure: Equatable {
        /// The server refused a group as private. It does not say which.
        case privateGroup
        case other
    }

    /// The groups on offer: the ones featured now, in their order, then the public groups the user
    /// has joined.
    private(set) var candidates: [Conversation]

    /// The chosen groups, in the order they will show on the profile.
    private(set) var selection: [ConversationID]

    private(set) var state: SaveState = .normal
    private(set) var loadState: LoadState = .loading

    /// Filters ``visibleCandidates`` by title.
    var query = ""

    /// A failed save, shown as a dialog. Set to nil once shown.
    var failure: Failure?

    @ObservationIgnored private var initialSelection: [ConversationID]
    @ObservationIgnored private let loadingFeatured: () async -> [Conversation]?
    @ObservationIgnored private let joinedGroups: () async -> [Conversation]
    @ObservationIgnored private let saving: ([ConversationID]) async throws -> [Conversation]
    @ObservationIgnored private let saved: ([Conversation]) -> Void

    /// - Parameters:
    ///   - featured: the groups the profile featured when last read, shown while they are re-read.
    ///   - loadingFeatured: re-reads the featured groups, in order; nil when that fails.
    ///   - joinedGroups: the groups the user is in, as the server says now.
    ///   - saving: submits the ordered selection and returns what is now featured.
    ///   - saved: hands that list to the rest of the app.
    init(
        featured: [Conversation],
        loadingFeatured: @escaping () async -> [Conversation]?,
        joinedGroups: @escaping () async -> [Conversation],
        saving: @escaping ([ConversationID]) async throws -> [Conversation],
        saved: @escaping ([Conversation]) -> Void
    ) {
        self.candidates = featured
        self.selection = featured.map(\.id)
        self.initialSelection = featured.map(\.id)
        self.loadingFeatured = loadingFeatured
        self.joinedGroups = joinedGroups
        self.saving = saving
        self.saved = saved
    }

    /// The candidates whose title matches ``query``.
    var visibleCandidates: [Conversation] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.groupLinkTitle.localizedCaseInsensitiveContains(query) }
    }

    /// Whether Save is enabled: only once the featured list has been read, so a save never drops
    /// groups the screen did not know about. Clearing every group is a change like any other.
    var canSave: Bool {
        state == .normal && loadState == .loaded && selection != initialSelection
    }

    /// Whether the group is chosen.
    func isSelected(_ id: ConversationID) -> Bool {
        selection.contains(id)
    }

    /// Whether tapping the group would change anything: always for a chosen one, and for the rest
    /// only while there is room under ``FeaturedGroups/limit``.
    func canToggle(_ id: ConversationID) -> Bool {
        state == .normal && (isSelected(id) || selection.count < FeaturedGroups.limit)
    }

    /// Chooses the group at the end of the order, or drops it.
    func toggle(_ id: ConversationID) {
        guard canToggle(id) else { return }
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
    }

    /// Re-reads the featured groups, then offers the user's joined public groups after them.
    ///
    /// Featured groups stay on offer even when the user has left them: leaving does not unfeature
    /// a group, so dropping it from the list would leave no way to remove it.
    func loadCandidates() async {
        guard let featured = await loadingFeatured() else {
            loadState = .failed
            return
        }
        let featuredIDs = featured.map(\.id)
        // A choice made while the list was loading stands; an untouched one follows the server.
        if selection == initialSelection {
            selection = featuredIDs
        }
        initialSelection = featuredIDs

        let joined = await joinedGroups()
        let known = Set(featuredIDs)
        candidates = featured + joined.filter { $0.type == .group && !$0.isPrivate && !known.contains($0.id) }
        loadState = .loaded
    }

    /// Submits the selection. Failures land in ``failure``.
    func save() async {
        guard canSave else { return }

        state = .saving

        do {
            let result = try await saving(selection)
            saved(result)
            state = .saved

        } catch let error as ErrorSetFeaturedGroups where error == .denied {
            state = .normal
            logger.info("Featured groups denied")
            ErrorReporting.captureError(error, reason: "Featured groups denied")
            failure = .privateGroup

        } catch {
            state = .normal
            guard !Task.isCancelled else { return }
            logger.error("Failed to set featured groups", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to set featured groups")
            failure = .other
        }
    }
}
