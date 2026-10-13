//
//  WebImageDiskCacheTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

/// Preview images on disk follow their rows' TTL and fit a fixed capacity (P22b, P22c).
@Suite("WebImageDiskCache")
struct WebImageDiskCacheTests {

    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private static let a = URL(string: "https://img.example.com/a.png")!
    private static let b = URL(string: "https://img.example.com/b.png")!
    private static let c = URL(string: "https://img.example.com/c.png")!

    private static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test func storedBytesReadBack() {
        let disk = WebImageDiskCache(directory: Self.directory())
        disk.store(Data([1, 2, 3]), for: Self.a)
        #expect(disk.data(for: Self.a) == Data([1, 2, 3]))
        #expect(disk.data(for: Self.b) == nil)
    }

    @Test func anImageExactlyAtTheResolvedTTLStillReads() {
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let disk = WebImageDiskCache(directory: Self.directory(), now: { clock.now })
        disk.store(Data([1]), for: Self.a)
        clock.now += WebLinks.resolvedTTL
        #expect(disk.data(for: Self.a) == Data([1]))
    }

    @Test func anImagePastTheResolvedTTLReadsAsNilAndIsDeleted() {
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let disk = WebImageDiskCache(directory: Self.directory(), now: { clock.now })
        disk.store(Data([1]), for: Self.a)
        clock.now += WebLinks.resolvedTTL + 1
        #expect(disk.data(for: Self.a) == nil)
        clock.now -= WebLinks.resolvedTTL
        #expect(disk.data(for: Self.a) == nil)
    }

    @Test func touchingAFileKeepsItAsLongAsItsRow() {
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let disk = WebImageDiskCache(directory: Self.directory(), now: { clock.now })
        disk.store(Data([1]), for: Self.a)
        clock.now += WebLinks.resolvedTTL - 10
        disk.touch(Self.a)
        clock.now += 20
        #expect(disk.data(for: Self.a) == Data([1]))
    }

    @MainActor
    @Test func reRecordingARowRestampsItsImage() async throws {
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let directory = Self.directory()
        let disk = WebImageDiskCache(directory: directory, now: { clock.now })
        disk.store(Data([1]), for: Self.a)
        let memo = LinkCardMemo(images: disk, now: { clock.now })
        clock.now += WebLinks.resolvedTTL - 10
        let restamped = clock.now
        memo.recordWeb(.resolved(.init(title: "T", description: nil, imageURL: Self.a, host: "example.com")), for: "web:https://example.com/")
        try await waitUntil {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return files.first.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate } == restamped
        }
        clock.now += 20
        #expect(disk.data(for: Self.a) == Data([1]))
    }

    @Test func overCapacityDropsTheOldestFirst() {
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let disk = WebImageDiskCache(directory: Self.directory(), capacity: 10, now: { clock.now })
        disk.store(Data(repeating: 1, count: 4), for: Self.a)
        clock.now += 1
        disk.store(Data(repeating: 2, count: 4), for: Self.b)
        clock.now += 1
        disk.store(Data(repeating: 3, count: 4), for: Self.c)
        #expect(disk.data(for: Self.a) == nil)
        #expect(disk.data(for: Self.b) != nil)
        #expect(disk.data(for: Self.c) != nil)
    }

    @Test func removeAllBeforeDropsOnlyOlderImages() {
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let disk = WebImageDiskCache(directory: Self.directory(), now: { clock.now })
        disk.store(Data([1]), for: Self.a)
        clock.now += 10
        disk.store(Data([2]), for: Self.b)
        disk.removeAll(before: clock.now - 5)
        #expect(disk.data(for: Self.a) == nil)
        #expect(disk.data(for: Self.b) == Data([2]))
    }

    @MainActor
    @Test func aRowReplacedWithADifferentImageDeletesTheOldImage() async throws {
        let disk = WebImageDiskCache(directory: Self.directory())
        disk.store(Data([1]), for: Self.a)
        let memo = LinkCardMemo(images: disk)
        let key = "web:https://example.com/"
        memo.recordWeb(.resolved(.init(title: "T", description: nil, imageURL: Self.a, host: "example.com")), for: key)
        memo.recordWeb(.none, for: key)
        try await waitUntil { disk.data(for: Self.a) == nil }
    }

    @MainActor
    @Test func aRowReRecordedWithTheSameImageKeepsIt() async throws {
        let disk = WebImageDiskCache(directory: Self.directory())
        disk.store(Data([1]), for: Self.a)
        let memo = LinkCardMemo(images: disk)
        let key = "web:https://example.com/"
        let page = LinkCard.Web.Resolved(title: "T", description: nil, imageURL: Self.a, host: "example.com")
        memo.recordWeb(.resolved(page), for: key)
        memo.recordWeb(.resolved(page), for: key)
        try await Task.sleep(for: .milliseconds(50))
        #expect(disk.data(for: Self.a) == Data([1]))
    }
}
