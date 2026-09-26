import Foundation
import Testing
import Logging
@testable import FlipcashCore

@Suite("LogStore Tests")
struct LogStoreTests {

    // The app bootstraps LoggingSystem at launch; this test host doesn't, so the
    // tests that write through a Logger install the handler here. A second
    // LoggingSystem.bootstrap traps, and tests run in parallel, so it goes through
    // a lazy static, which Swift initializes exactly once.
    private static let bootstrapLogging: Void = LogStore.bootstrap()

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
        _ = Self.bootstrapLogging
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

    @Test("flush writes buffered lines to a log file")
    func flushWritesBufferedLines() async throws {
        _ = Self.bootstrapLogging
        let logger = Logger(label: "test.flush")
        let marker = "flush check \(UUID().uuidString)"
        logger.info("\(marker)")

        await LogStore.shared.flush()

        let files = await LogStore.shared.fileWriter.logFileURLs()
        let contents = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(contents.contains { $0.contains(marker) })
    }
}
