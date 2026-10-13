//
//  LinkPreviewStoreTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashStore
@testable import Flipcash

@Suite("LinkPreview store")
struct LinkPreviewStoreTests {

    private let epoch = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test("Upsert then read back returns the stored row")
    func upsertAndRead() throws {
        let database = try Database.mock
        let json = Data("a".utf8)
        try database.upsertLinkPreview(key: "k", json: json, updatedAt: epoch)

        let rows = try database.linkPreviews(since: .distantPast)
        #expect(rows == [LinkPreviewRow(key: "k", json: json, updatedAt: epoch)])
    }

    @Test("Upserting the same key replaces the row")
    func upsertReplaces() throws {
        let database = try Database.mock
        try database.upsertLinkPreview(key: "k", json: Data("a".utf8), updatedAt: epoch)
        try database.upsertLinkPreview(key: "k", json: Data("b".utf8), updatedAt: epoch.addingTimeInterval(10))

        let rows = try database.linkPreviews(since: .distantPast)
        #expect(rows.count == 1)
        #expect(rows[0].json == Data("b".utf8))
        #expect(rows[0].updatedAt == epoch.addingTimeInterval(10))
    }

    @Test("linkPreviews(since:) excludes older rows")
    func sinceExcludesOlder() throws {
        let database = try Database.mock
        try database.upsertLinkPreview(key: "old", json: Data(), updatedAt: epoch)
        try database.upsertLinkPreview(key: "edge", json: Data(), updatedAt: epoch.addingTimeInterval(100))
        try database.upsertLinkPreview(key: "new", json: Data(), updatedAt: epoch.addingTimeInterval(200))

        let keys = try database.linkPreviews(since: epoch.addingTimeInterval(100)).map(\.key)
        #expect(Set(keys) == ["edge", "new"])
    }

    @Test("deleteLinkPreviews(before:) removes only older rows")
    func deleteBefore() throws {
        let database = try Database.mock
        try database.upsertLinkPreview(key: "old", json: Data(), updatedAt: epoch)
        try database.upsertLinkPreview(key: "edge", json: Data(), updatedAt: epoch.addingTimeInterval(100))
        try database.upsertLinkPreview(key: "new", json: Data(), updatedAt: epoch.addingTimeInterval(200))

        try database.deleteLinkPreviews(before: epoch.addingTimeInterval(100))

        let keys = try database.linkPreviews(since: .distantPast).map(\.key)
        #expect(Set(keys) == ["edge", "new"])
    }
}
