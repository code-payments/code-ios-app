//
//  ChatArchiveStore.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

/// The archive writes this device has not had confirmed, and the archive cache the extensions read.
///
/// The server holds archive state (`ViewerState.settings.archive`), and ``ConversationController``
/// reads it from each chat's viewer state. This store holds what the server doesn't have yet: an
/// archive or unarchive the user asked for whose RPC has not succeeded, and the records this device
/// kept before the server stored archive state, which upload as archive writes. The controller lays
/// ``pending`` over the server's state for everything the list derives.
///
/// The app is the only writer; the NotificationService extension reads the same file through
/// ``ChatArchiveReader``. Writes are immediate and atomic rather than debounced like drafts: archive
/// changes are rare, and a push arriving in the next second must already see them.
///
/// Archive is never mapped through `isHidden`, which comes from the server's blocklist and is
/// rewritten on every sync.
@MainActor
@Observable
final class ChatArchiveStore {

    /// Archive (`true`) and unarchive (`false`) writes the server has not confirmed. Tracked: the
    /// list, chips, Archived row and tab badge all derive from it.
    private(set) var pending: [ConversationID: Bool]

    /// Whether every record this device kept before the server stored archive state has been
    /// resolved against the server. Persisted per account.
    private(set) var isUploaded: Bool

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let owner: PublicKey
    @ObservationIgnored private var file: ChatArchiveFile

    /// A file that cannot be read is treated as an empty archive; refusing to start the session over
    /// it would be worse, and the user can simply archive again.
    ///
    /// A file written before the server stored archive state has no pending writes recorded; its
    /// records become archive writes here, and are written back as such so a later launch doesn't
    /// mistake the cache for them.
    init(directory: URL, owner: PublicKey) {
        self.directory = directory
        self.owner = owner
        var file = ChatArchiveReader.load(owner: owner, directory: directory) ?? ChatArchiveFile()
        let pending = file.pendingWrites
        let seeded = file.pending == nil
        file.setPendingWrites(pending)
        self.file = file
        self.pending = pending
        self.isUploaded = file.uploaded == true
        if seeded {
            write()
        }
    }

    /// Records that the user asked for `id` to be archived (`true`) or unarchived (`false`).
    func request(_ archive: Bool, for id: ConversationID) {
        guard pending[id] != archive else { return }
        pending[id] = archive
        commitPending()
    }

    /// Drops the write for `id` if it still asks for `archive`, and reports whether it did. A write
    /// the user changed while the RPC was in flight stays, so the caller sends it next.
    @discardableResult
    func resolve(_ id: ConversationID, ifRequested archive: Bool) -> Bool {
        guard pending[id] == archive else { return false }
        pending[id] = nil
        commitPending()
        return true
    }

    /// Forgets `id` entirely, for a chat the user left or was removed from. The server clears its
    /// archive then, so nothing is sent.
    func drop(_ id: ConversationID) {
        let hadWrite = pending.removeValue(forKey: id) != nil
        let wasCached = file.unarchive(id)
        guard hadWrite || wasCached else { return }
        file.setPendingWrites(pending)
        write()
    }

    /// The chats the extensions' cache holds as archived.
    var cachedIDs: Set<ConversationID> {
        file.archivedIDs
    }

    /// Replaces the extensions' cache with `archived`, the chats the app now shows as archived.
    /// Writes only when it changed.
    func updateCache(_ archived: [ConversationID: Date]) {
        var updated = file
        updated.setArchived(archived)
        guard updated != file else { return }
        file = updated
        write()
    }

    /// Records that every pre-server record has been resolved.
    func markUploaded() {
        guard !isUploaded else { return }
        isUploaded = true
        file.uploaded = true
        write()
    }

    /// Records the viewer's handle for the extension, which cannot read the profile.
    func setViewerUsername(_ username: Username?) {
        let value = username?.value
        guard file.viewerUsername != value else { return }
        file.viewerUsername = value
        write()
    }

    private func commitPending() {
        file.setPendingWrites(pending)
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
