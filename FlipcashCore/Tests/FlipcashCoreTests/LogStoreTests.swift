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
            label: "test",
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

    @Test("exported log file starts with the device header")
    func exportedLogStartsWithHeader() async throws {
        // The app bootstraps LoggingSystem at launch; this test host doesn't, so
        // install the handler here. LoggingSystem.bootstrap is a process-global,
        // one-time call -- safe to repeat since FlipcashLogHandler is idempotent
        // to install (last writer wins) and no other test in this process needs
        // a different configuration.
        LogStore.bootstrap()
        let logger = Logger(label: "test.export")
        logger.info("export header check")

        let url = try await LogStore.shared.exportLogs()
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.hasPrefix("=========="))
        #expect(contents.contains("DEVICE & APP INFO"))
        #expect(contents.contains("OCP Contract:"))
        #expect(contents.contains("FC2 Contract:"))
    }
}
