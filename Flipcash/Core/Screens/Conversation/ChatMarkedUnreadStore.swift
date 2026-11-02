//
//  ChatMarkedUnreadStore.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

/// The chats the user has marked unread. Every caller reads and writes through this, so a
/// server-backed store can replace the local one without any caller changing.
///
/// `markedIDs` must be observable: the list projection reads it, and the rows, chips and tab badge
/// re-render when it changes.
@MainActor
protocol ChatMarkedUnreadStore: AnyObject {

    /// The marked chats.
    var markedIDs: Set<ConversationID> { get }

    /// Marks one chat.
    func mark(_ id: ConversationID)

    /// Clears one chat's mark.
    func clear(_ id: ConversationID)

    /// Clears the mark on each of `ids`.
    func clear(_ ids: Set<ConversationID>)
}

/// The device-only ``ChatMarkedUnreadStore``: a JSON file beside the drafts in Application Support,
/// owner-scoped like ``ChatArchiveStore``, so each account keeps its own marks across logout. Outside `FlipcashStore`, whose version bump deletes the
/// database, because nothing can re-fetch a mark until the server stores it.
@MainActor
@Observable
final class LocalChatMarkedUnreadStore: ChatMarkedUnreadStore {

    private(set) var markedIDs: Set<ConversationID>

    @ObservationIgnored private let url: URL

    /// A file that cannot be read is treated as no marks; the user can mark again.
    init(directory: URL, owner: PublicKey) {
        self.url = directory.appendingPathComponent("flipcash-\(owner.base58)-marked-unread.json")
        let keys = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        self.markedIDs = Set(keys.compactMap { Data(base64Encoded: $0).map(ConversationID.init(data:)) })
    }

    func mark(_ id: ConversationID) {
        guard !markedIDs.contains(id) else { return }
        markedIDs.insert(id)
        write()
    }

    func clear(_ id: ConversationID) {
        guard markedIDs.contains(id) else { return }
        markedIDs.remove(id)
        write()
    }

    func clear(_ ids: Set<ConversationID>) {
        guard !markedIDs.isDisjoint(with: ids) else { return }
        markedIDs.subtract(ids)
        write()
    }

    /// Keys as ``ChatArchiveFile/key(_:)`` does: base64 of the id's bytes, which fits both the
    /// 32-byte DM shape and a group's 16 bytes.
    private func write() {
        do {
            let keys = markedIDs.map { $0.data.base64EncodedString() }.sorted()
            try JSONEncoder().encode(keys).write(to: url, options: .atomic)
        } catch {
            ErrorReporting.captureError(error, reason: "Failed to write marked-unread chats")
        }
    }
}
