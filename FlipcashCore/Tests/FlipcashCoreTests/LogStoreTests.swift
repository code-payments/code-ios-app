import Foundation
import Testing
import Logging
@testable import FlipcashCore

@Suite("LogStore Tests")
struct LogStoreTests {

    @Test("recentEntries returns formatted strings from ring buffer")
    func recentEntriesReturnsFormattedStrings() {
        let store = LogStore.shared
        let storage = store.ringBuffer

        storage.append(LogEntry(
            timestamp: Date(),
            level: .info,
            message: "test entry",
            metadata: nil,
            source: "test",
            function: "test()",
            file: "Test.swift",
            line: 1
        ))

        let entries = store.recentEntries(last: 1)
        #expect(entries.count == 1)
        #expect(entries[0].contains("[INFO]"))
        #expect(entries[0].contains("test entry"))
    }

    @Test("recentEntries default returns up to 100")
    func recentEntriesDefault() {
        let store = LogStore.shared
        let entries = store.recentEntries()
        #expect(entries.count <= 100)
    }
}
