import Foundation
import Testing
import Logging
@testable import FlipcashCore

@Suite("LogEntry Tests")
struct LogEntryTests {

    @Test("formatted() produces expected single-line output without metadata")
    func formattedWithoutMetadata() {
        let entry = LogEntry(
            timestamp: makeDate(hour: 10, minute: 32, second: 15, millisecond: 1234),
            level: .info,
            message: "Rate fetched",
            metadata: nil,
            label: "flipcash.rates-controller",
            source: "FlipcashCore",
            function: "fetchRates()",
            file: "RatesController.swift",
            line: 42
        )

        let result = entry.formatted()

        #expect(result.contains("[INFO]"))
        #expect(result.contains("flipcash.rates-controller"))
        #expect(result.contains("Rate fetched"))
        #expect(!result.contains("="))
    }

    @Test("formatted() includes metadata as key=value pairs")
    func formattedWithMetadata() {
        let entry = LogEntry(
            timestamp: makeDate(hour: 10, minute: 32, second: 15, millisecond: 1234),
            level: .warning,
            message: "Stale rate",
            metadata: ["currency": "USD", "age": "120"],
            label: "flipcash.rates-controller",
            source: "FlipcashCore",
            function: "fetchRates()",
            file: "RatesController.swift",
            line: 42
        )

        let result = entry.formatted()

        #expect(result.contains("[WARNING]"))
        #expect(result.contains("Stale rate"))
        #expect(result.contains("currency=USD"))
        #expect(result.contains("age=120"))
    }

    @Test("formatted() prints the Logger label, not the module-name source")
    func formattedPrintsLabelNotSource() {
        let entry = LogEntry(
            timestamp: makeDate(hour: 10, minute: 32, second: 15, millisecond: 0),
            level: .info,
            message: "Rate fetched",
            metadata: nil,
            label: "flipcash.rates-controller",
            source: "FlipcashCore",
            function: "fetchRates()",
            file: "RatesController.swift",
            line: 42
        )

        let result = entry.formatted()

        #expect(result.contains("flipcash.rates-controller"))
        #expect(!result.contains("FlipcashCore"))
    }

    @Test("formatted() uses uppercase level labels")
    func formattedLevelLabels() {
        let levels: [(Logger.Level, String)] = [
            (.debug, "DEBUG"),
            (.info, "INFO"),
            (.notice, "NOTICE"),
            (.warning, "WARNING"),
            (.error, "ERROR"),
            (.critical, "CRITICAL"),
        ]

        for (level, expected) in levels {
            let entry = LogEntry(
                timestamp: makeDate(hour: 12, minute: 0, second: 0, millisecond: 0),
                level: level,
                message: "test",
                metadata: nil,
                label: "test",
                source: "test",
                function: "test()",
                file: "Test.swift",
                line: 1
            )
            #expect(entry.formatted().contains("[\(expected)]"))
        }
    }

    // MARK: - Helpers

    private func makeDate(hour: Int, minute: Int, second: Int, millisecond: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 26
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = millisecond * 1_000_000
        return Calendar.current.date(from: components)!
    }
}
