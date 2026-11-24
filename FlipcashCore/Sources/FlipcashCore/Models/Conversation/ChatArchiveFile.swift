//
//  ChatArchiveFile.swift
//  FlipcashCore
//

import Foundation

/// The on-disk archive record, shared by the app (the only writer) and the NotificationService
/// extension (read-only). One type for both so the two processes cannot drift apart on the format.
///
/// Lives in the App Group container rather than Application Support, where `ChatDraftStore` writes:
/// the extension needs archive state to decide whether a push may interrupt, and it can read only
/// the group container. Not in `FlipcashStore` either, whose version bump deletes the store; the
/// pending writes and the records not yet uploaded cannot be re-fetched from the server.
///
/// The server holds archive state now (`ViewerState.settings.archive`), and the file is its cache:
/// ``archived`` is what the app last showed as archived, for the extensions to read. ``pending`` and
/// ``uploaded`` are the app's alone. Both are optional and the version stays 1, so a file written
/// before the server held archive state still reads, and its records become the first upload.
public struct ChatArchiveFile: Codable, Equatable, Sendable {

    public static let version = 1

    public var version: Int
    /// The viewer's lowercase handle, so the extension can recognise an @mention of the viewer
    /// without access to the app's profile. `nil` until the profile has loaded.
    public var viewerUsername: String?
    /// Archived chats by ``key(_:)``, with when each was archived: the server's archived chats with
    /// the pending writes laid over them.
    public var archived: [String: Date]
    /// Archive (`true`) and unarchive (`false`) requests by ``key(_:)`` that the server has not
    /// confirmed. `nil` only in a file written before the server held archive state; read it
    /// through ``pendingWrites``.
    public var pending: [String: Bool]?
    /// Set once every record this device held before the server stored archive state has been
    /// resolved against the server. From then on the server's state wins.
    public var uploaded: Bool?

    public init(viewerUsername: String? = nil, archived: [String: Date] = [:], pending: [String: Bool]? = [:], uploaded: Bool? = nil) {
        self.version = Self.version
        self.viewerUsername = viewerUsername
        self.archived = archived
        self.pending = pending
        self.uploaded = uploaded
    }

    /// The writes the server has not confirmed. A file written before the server held archive state
    /// has no ``pending``, and each of its records is an archive still to upload.
    public var pendingWrites: [ConversationID: Bool] {
        guard let pending else {
            guard uploaded != true else { return [:] }
            return Dictionary(archivedIDs.map { ($0, true) }, uniquingKeysWith: { first, _ in first })
        }
        return Dictionary(pending.compactMap { key, desired in Self.id(key).map { ($0, desired) } }, uniquingKeysWith: { first, _ in first })
    }

    /// Replaces ``pending`` with `writes`.
    public mutating func setPendingWrites(_ writes: [ConversationID: Bool]) {
        pending = Dictionary(writes.map { (Self.key($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// Replaces ``archived`` with `archived`, keeping the date already recorded for a chat that
    /// stays archived.
    public mutating func setArchived(_ archived: [ConversationID: Date]) {
        let current = self.archived
        self.archived = Dictionary(archived.map { id, date in
            let key = Self.key(id)
            return (key, current[key] ?? date)
        }, uniquingKeysWith: { first, _ in first })
    }

    public func isArchived(_ id: ConversationID) -> Bool {
        archived[Self.key(id)] != nil
    }

    public mutating func archive(_ id: ConversationID, at date: Date) {
        archived[Self.key(id)] = date
    }

    @discardableResult
    public mutating func unarchive(_ id: ConversationID) -> Bool {
        archived.removeValue(forKey: Self.key(id)) != nil
    }

    /// Every archived chat's id. Keys that do not decode are dropped.
    public var archivedIDs: Set<ConversationID> {
        Set(archived.keys.compactMap(Self.id))
    }

    private static func id(_ key: String) -> ConversationID? {
        Data(base64Encoded: key).map(ConversationID.init(data:))
    }

    /// Base64 of the id's own bytes, as `ChatDraftStore` keys drafts: `base64URLEncoded` decodes only
    /// the 32-byte DM shape, and a group's id is 16 bytes.
    public static func key(_ id: ConversationID) -> String {
        id.data.base64EncodedString()
    }

    public static func filename(owner: PublicKey) -> String {
        "flipcash-\(owner.base58)-archive.json"
    }

    /// The App Group container, or `nil` where the entitlement is absent (unit tests, some previews).
    public static var appGroupDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NotificationPreviewCache.appGroup)
    }

    /// Writes atomically (temp file, then rename) because two processes touch the file and the
    /// reader must never see a half-written one.
    public func write(owner: PublicKey, directory: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: directory.appendingPathComponent(Self.filename(owner: owner)), options: .atomic)
    }
}

/// Read-only access for the NotificationService extension and the foreground push path.
public enum ChatArchiveReader {

    /// The owner's archive record, or `nil` when there is none, it is unreadable, or it was written
    /// by another schema version. All four mean "no archive information", and the caller treats that
    /// as not archived: a push that cannot prove its chat is archived presents normally.
    public static func load(owner: PublicKey, directory: URL? = nil) -> ChatArchiveFile? {
        guard let directory = directory ?? ChatArchiveFile.appGroupDirectory else { return nil }
        let url = directory.appendingPathComponent(ChatArchiveFile.filename(owner: owner))
        guard
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(ChatArchiveFile.self, from: data),
            file.version == ChatArchiveFile.version
        else { return nil }
        return file
    }
}
