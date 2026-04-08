import Foundation
import Testing
import Logging
@testable import FlipcashCore

@Suite("RingBufferLogHandler Tests")
struct RingBufferLogHandlerTests {

    @Test("Appending entries within capacity preserves all")
    func appendWithinCapacity() {
        let storage = RingBufferStorage(capacity: 5)
        for i in 0..<5 {
            storage.append(makeEntry(message: "msg-\(i)"))
        }

        let entries = storage.entries()
        #expect(entries.count == 5)
        #expect(entries[0].message == "msg-0")
        #expect(entries[4].message == "msg-4")
    }

    @Test("Appending beyond capacity evicts oldest entries")
    func appendBeyondCapacity() {
        let storage = RingBufferStorage(capacity: 3)
        for i in 0..<5 {
            storage.append(makeEntry(message: "msg-\(i)"))
        }

        let entries = storage.entries()
        #expect(entries.count == 3)
        #expect(entries[0].message == "msg-2")
        #expect(entries[1].message == "msg-3")
        #expect(entries[2].message == "msg-4")
    }

    @Test("entries(last:) returns only the requested count")
    func entriesLastN() {
        let storage = RingBufferStorage(capacity: 10)
        for i in 0..<10 {
            storage.append(makeEntry(message: "msg-\(i)"))
        }

        let entries = storage.entries(last: 3)
        #expect(entries.count == 3)
        #expect(entries[0].message == "msg-7")
        #expect(entries[1].message == "msg-8")
        #expect(entries[2].message == "msg-9")
    }

    @Test("entries(last:) with count larger than buffer returns all")
    func entriesLastMoreThanAvailable() {
        let storage = RingBufferStorage(capacity: 5)
        for i in 0..<3 {
            storage.append(makeEntry(message: "msg-\(i)"))
        }

        let entries = storage.entries(last: 10)
        #expect(entries.count == 3)
    }

    @Test("Empty buffer returns empty array")
    func emptyBuffer() {
        let storage = RingBufferStorage(capacity: 5)
        #expect(storage.entries().isEmpty)
    }

    // MARK: - Helpers

    private func makeEntry(message: String) -> LogEntry {
        LogEntry(
            timestamp: Date(),
            level: .info,
            message: message,
            metadata: nil,
            label: "test",
            source: "test",
            function: "test()",
            file: "Test.swift",
            line: 1
        )
    }
}
