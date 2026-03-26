import Foundation
import Logging

/// Central logging coordinator.
///
/// Owns the ring buffer and file writer, provides bootstrap
/// and the public API for Bugsnag enrichment and log export.
public final class LogStore: Sendable {

    public static let shared = LogStore()

    public let ringBuffer: RingBufferStorage
    let fileWriter: FileWriterActor

    private init() {
        self.ringBuffer = RingBufferStorage(capacity: 100)

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let logsDir = caches.appendingPathComponent("Logs", isDirectory: true)
        self.fileWriter = FileWriterActor(directory: logsDir)
    }

    // MARK: - Bootstrap

    /// Call once at app launch, before any logging.
    ///
    /// Registers a `MultiplexLogHandler` with swift-log that dispatches
    /// to console, ring buffer, and rotating file handlers.
    public static func bootstrap(middleware: [LogMiddleware] = []) {
        let store = LogStore.shared

        LoggingSystem.bootstrap { label in
            var consoleHandler = ConsoleLogHandler(middleware: middleware)
            var ringHandler = RingBufferLogHandler(storage: store.ringBuffer, middleware: middleware)
            var fileHandler = RotatingFileLogHandler(fileWriter: store.fileWriter, middleware: middleware)

            #if DEBUG
            let level = Logger.Level.debug
            #else
            let level = Logger.Level.info
            #endif

            consoleHandler.logLevel = level
            ringHandler.logLevel = level
            fileHandler.logLevel = level

            return MultiplexLogHandler([consoleHandler, ringHandler, fileHandler])
        }
    }

    // MARK: - Public API

    /// Returns the most recent log entries as formatted strings.
    /// Synchronous — safe to call from `ErrorReporting.capture()`.
    public func recentEntries(last: Int = 100) -> [String] {
        ringBuffer.entries(last: last).map { $0.formatted() }
    }

    /// Compresses all log files into a temporary `.zip` and returns the URL.
    ///
    /// This is a deliberate user action ("Send Logs"), so surfacing
    /// errors via `throws` is appropriate.
    public func exportCompressedLogs() async throws -> URL {
        let logFiles = await fileWriter.logFileURLs()

        guard !logFiles.isEmpty else {
            throw LogExportError.noLogsAvailable
        }

        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent("flipcash-logs-\(dateStamp()).zip")

        // Remove any prior export
        try? FileManager.default.removeItem(at: zipURL)

        // Concatenate all log files into a single file, then compress
        var combinedData = Data()
        for file in logFiles {
            if let data = try? Data(contentsOf: file) {
                combinedData.append(data)
            }
        }

        let compressedData = try (combinedData as NSData).compressed(using: .lzfse) as Data
        try compressedData.write(to: zipURL)

        return zipURL
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}

// MARK: - Errors

public enum LogExportError: Error, LocalizedError {
    case noLogsAvailable

    public var errorDescription: String? {
        switch self {
        case .noLogsAvailable:
            "No log files available to export."
        }
    }
}
