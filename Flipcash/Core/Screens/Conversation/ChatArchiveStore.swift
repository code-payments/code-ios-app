//
//  ChatArchiveStore.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

/// The chats this device's user has archived.
///
/// The app is the only writer; the NotificationService extension reads the same file through
/// ``ChatArchiveReader``. Writes are immediate and atomic rather than debounced like drafts: archive
/// changes are rare, and a push arriving in the next second must already see them.
///
/// `archivedIDs` is a tracked property, so anything reading ``ConversationController``'s list
/// projection re-renders when it changes. Archive is never mapped through `isHidden` — that flag
/// comes from the server's blocklist and is rewritten on every sync.
@MainActor
@Observable
final class ChatArchiveStore {

    /// Tracked: the list, chips, Archived row and tab badge all derive from it.
    private(set) var archivedIDs: Set<ConversationID>

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let owner: PublicKey
    @ObservationIgnored private var file: ChatArchiveFile

    /// A file that cannot be read is treated as an empty archive; refusing to start the session over
    /// it would be worse, and the user can simply archive again.
    init(directory: URL, owner: PublicKey) {
        self.directory = directory
        self.owner = owner
        self.file = ChatArchiveReader.load(owner: owner, directory: directory) ?? ChatArchiveFile()
        self.archivedIDs = file.archivedIDs
    }

    func isArchived(_ id: ConversationID) -> Bool {
        archivedIDs.contains(id)
    }

    func archive(_ id: ConversationID) {
        guard !archivedIDs.contains(id) else { return }
        file.archive(id, at: .now)
        commit()
    }

    func unarchive(_ id: ConversationID) {
        guard file.unarchive(id) else { return }
        commit()
    }

    /// Records the viewer's handle for the extension, which cannot read the profile.
    func setViewerUsername(_ username: Username?) {
        let value = username?.value
        guard file.viewerUsername != value else { return }
        file.viewerUsername = value
        write()
    }

    private func commit() {
        archivedIDs = file.archivedIDs
        write()
    }

    private func write() {
        do {
            try file.write(owner: owner, directory: directory)
        } catch {
            ErrorReporting.captureError(error, reason: "Failed to write chat archive")
        }
    }
}
