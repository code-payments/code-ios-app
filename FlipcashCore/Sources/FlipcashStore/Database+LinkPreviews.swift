//
//  Database+LinkPreviews.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import SQLite

/// One cached web link preview answer as stored, before decoding.
public struct LinkPreviewRow: Sendable, Equatable {
    public let key: String
    public let json: Data
    public let updatedAt: Date

    public init(key: String, json: Data, updatedAt: Date) {
        self.key = key
        self.json = json
        self.updatedAt = updatedAt
    }
}

nonisolated extension Database {

    /// The cached link previews written at or after `since`.
    public func linkPreviews(since: Date) throws -> [LinkPreviewRow] {
        let t = LinkPreviewTable()
        let query = t.table.filter(t.updatedAt >= since.timeIntervalSinceReferenceDate)
        return try reader.prepareRowIterator(query).map { row in
            LinkPreviewRow(
                key: row[t.key],
                json: row[t.json],
                updatedAt: Date(timeIntervalSinceReferenceDate: row[t.updatedAt])
            )
        }
    }

    /// Insert or replace the cached link preview for `key`.
    public func upsertLinkPreview(key: String, json: Data, updatedAt: Date) throws {
        try write { writer in
            let t = LinkPreviewTable()
            try writer.run(t.table.upsert(
                t.key       <- key,
                t.json      <- json,
                t.updatedAt <- updatedAt.timeIntervalSinceReferenceDate,
                onConflictOf: t.key
            ))
        }
    }

    /// Remove cached link previews written before `before`.
    public func deleteLinkPreviews(before: Date) throws {
        try write { writer in
            let t = LinkPreviewTable()
            try writer.run(t.table.filter(t.updatedAt < before.timeIntervalSinceReferenceDate).delete())
        }
    }
}
