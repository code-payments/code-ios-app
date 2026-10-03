//
//  PendingMediaStore.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.pending-media-store")

/// The photo sends that have left the composer but not yet been confirmed, kept on disk so a send
/// survives iOS killing the app while it is backgrounded.
///
/// A JSON manifest plus one JPEG per photo, owner-scoped in Application Support and outside
/// `FlipcashStore` for the reasons `ChatDraftStore` gives: that store is rebuilt from the server on
/// a version bump, and an unsent photo cannot be re-fetched.
@MainActor
final class PendingMediaStore {

    /// One photo send, as `ChatMediaSendPlan` assigned it.
    struct Entry: Codable, Equatable, Sendable {
        var clientMessageID: UUID
        /// The raw bytes of the chat's `ConversationID`.
        var conversationID: Data
        var createdAt: Date
        var fileName: String
        var caption: String?
        var replyTo: MessageID?
        /// The photo once its bytes are stored; nil while the encoded JPEG is the only thing held.
        var stored: UploadedPhoto?

        init(clientMessageID: UUID, conversationID: ConversationID, createdAt: Date, caption: String?, replyTo: MessageID?, stored: UploadedPhoto? = nil) {
            self.clientMessageID = clientMessageID
            self.conversationID = conversationID.data
            self.createdAt = createdAt
            self.fileName = "\(clientMessageID.uuidString).jpg"
            self.caption = caption
            self.replyTo = replyTo
            self.stored = stored
        }

        /// The chat the photo is being sent to.
        var chatID: ConversationID { ConversationID(data: conversationID) }
    }

    private struct File: Codable {
        var version: Int
        var entries: [Entry]
    }

    private static let version = 1

    private let manifestURL: URL
    private let photosDirectory: URL
    private var held: [Entry]

    /// Loads the owner's pending sends. A manifest that cannot be read is treated as empty.
    init(directory: URL, owner: PublicKey) {
        let prefix = "flipcash-\(owner.base58)-pending-media"
        self.manifestURL = directory.appendingPathComponent("\(prefix).json")
        self.photosDirectory = directory.appendingPathComponent(prefix, isDirectory: true)
        guard
            let data = try? Data(contentsOf: manifestURL),
            let file = try? JSONDecoder().decode(File.self, from: data),
            file.version == Self.version
        else {
            self.held = []
            return
        }
        self.held = file.entries
    }

    /// Every send still held, oldest first.
    var entries: [Entry] { held }

    /// Starts holding `entry`, replacing one with the same client id.
    func add(_ entry: Entry) {
        held.removeAll { $0.clientMessageID == entry.clientMessageID }
        held.append(entry)
        writeManifest()
    }

    /// Writes the encoded JPEG for a held send, so the photo survives a kill from here on.
    func writeImage(_ data: Data, for clientMessageID: UUID) {
        guard let entry = held.first(where: { $0.clientMessageID == clientMessageID }) else { return }
        do {
            try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
            try data.write(to: photosDirectory.appendingPathComponent(entry.fileName), options: .atomic)
        } catch {
            ErrorReporting.captureError(error, reason: "Failed to write pending chat photo")
        }
    }

    /// The JPEG held for `entry`, or nil when its file is gone.
    func imageData(for entry: Entry) -> Data? {
        try? Data(contentsOf: photosDirectory.appendingPathComponent(entry.fileName))
    }

    /// Records that the send's bytes are stored, so a relaunch resumes instead of uploading again.
    func setStored(_ photo: UploadedPhoto, for clientMessageID: UUID) {
        guard let index = held.firstIndex(where: { $0.clientMessageID == clientMessageID }) else { return }
        held[index].stored = photo
        writeManifest()
    }

    /// Forgets a send and deletes its photo — confirmed, discarded, or refused for good.
    func remove(clientMessageID: UUID) {
        guard let index = held.firstIndex(where: { $0.clientMessageID == clientMessageID }) else { return }
        let entry = held.remove(at: index)
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(entry.fileName))
        writeManifest()
    }

    /// Drops entries whose photo file is missing and deletes photo files no entry refers to.
    func sweepOrphans() {
        let before = held.count
        held.removeAll { imageData(for: $0) == nil }
        if held.count != before { writeManifest() }

        let known = Set(held.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: photosDirectory.path)) ?? []
        for name in files where !known.contains(name) {
            try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(name))
        }
        if before != held.count || files.count != known.count {
            logger.info("Swept orphaned pending photos", metadata: [
                "droppedEntries": "\(before - held.count)",
                "files": "\(files.count)",
            ])
        }
    }

    private func writeManifest() {
        do {
            let data = try JSONEncoder().encode(File(version: Self.version, entries: held))
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            ErrorReporting.captureError(error, reason: "Failed to write pending chat photo manifest")
        }
    }
}
