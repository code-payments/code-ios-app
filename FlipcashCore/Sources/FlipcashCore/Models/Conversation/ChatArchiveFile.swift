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
/// the group container. Not in `FlipcashStore` either, whose version bump deletes the store; an
/// archive set cannot be re-fetched until the server stores it.
public struct ChatArchiveFile: Codable, Equatable, Sendable {

    public static let version = 1

    public var version: Int
    /// The viewer's lowercase handle, so the extension can recognise an @mention of the viewer
    /// without access to the app's profile. `nil` until the profile has loaded.
    public var viewerUsername: String?
    /// Archived chats by ``key(_:)``, with when each was archived.
    public var archived: [String: Date]

    public init(viewerUsername: String? = nil, archived: [String: Date] = [:]) {
        self.version = Self.version
        self.viewerUsername = viewerUsername
        self.archived = archived
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
        Set(archived.keys.compactMap { Data(base64Encoded: $0).map(ConversationID.init(data:)) })
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
