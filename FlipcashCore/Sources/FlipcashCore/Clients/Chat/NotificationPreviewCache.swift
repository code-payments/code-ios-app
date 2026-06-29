//
//  NotificationPreviewCache.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A tiny shared-container cache for a conversation's rendered preview. The notification SERVICE
/// extension writes it on push arrival; the CONTENT extension reads it on expand — so the content
/// extension renders instantly without opening a gRPC connection (no resident NIO/HTTP2 stack on
/// the open path). Best-effort: a miss just means the content extension does a live fetch instead.
public enum NotificationPreviewCache {

    /// The App Group shared by the app + both notification extensions.
    public static let appGroup = "group.com.flipcash.shared"

    /// How many recent rows the service prefetches and the content extension shows. Centralized
    /// so the cached preview and any live fallback fetch use the same depth.
    public static let previewLimit = 5

    /// Writes the rendered preview for a conversation. Best-effort.
    public static func write(_ items: [ChatItem], for conversationID: ConversationID) {
        guard let url = fileURL(for: conversationID) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(items).write(to: url, options: .atomic)
        } catch {
            // Best-effort cache — a write failure just falls back to a live fetch on open.
        }
    }

    /// The cached preview for a conversation, or nil when nothing is cached or it can't be decoded.
    public static func read(for conversationID: ConversationID) -> [ChatItem]? {
        guard let url = fileURL(for: conversationID), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([ChatItem].self, from: data)
    }

    /// Deletes every cached preview. Call on logout so chat snippets don't outlive the session — the
    /// cached JSON holds rendered message text + amounts in cleartext in the App Group container.
    public static func clear() {
        guard let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("ChatPreviews", isDirectory: true)
        else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// The cache file for a conversation. `base64URLEncoded` is already filename-safe (URL-safe,
    /// unpadded), so it doubles as the file name.
    private static func fileURL(for conversationID: ConversationID) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("ChatPreviews", isDirectory: true)
            .appendingPathComponent("\(conversationID.base64URLEncoded).json")
    }
}
