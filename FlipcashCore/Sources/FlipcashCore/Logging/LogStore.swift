import Foundation
import Logging

/// Central logging coordinator.
///
/// Owns the ring buffer and file writer, provides bootstrap
/// and the public API for Bugsnag enrichment and log export.
public final class LogStore: Sendable {

    public static let shared = LogStore()

    let ringBuffer: RingBufferStorage
    let fileWriter: FileWriterActor
    let fileBuffer: FileWriteBuffer

    private init() {
        self.ringBuffer = RingBufferStorage(capacity: 100)

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let logsDir = caches.appendingPathComponent("Logs", isDirectory: true)
        self.fileWriter = FileWriterActor(directory: logsDir)
        self.fileBuffer = FileWriteBuffer(writer: fileWriter)
    }

    // MARK: - Bootstrap

    /// Call once at app launch, before any logging.
    ///
    /// Registers a single `FlipcashLogHandler` that processes each entry
    /// once and dispatches to console, ring buffer, and file writer.
    public static func bootstrap(middleware: [LogMiddleware] = []) {
        let store = LogStore.shared

        #if DEBUG
        let level = Logger.Level.debug
        #else
        let level = Logger.Level.info
        #endif

        LoggingSystem.bootstrap { _ in
            FlipcashLogHandler(
                logLevel: level,
                ringBuffer: store.ringBuffer,
                fileBuffer: store.fileBuffer,
                middleware: middleware
            )
        }
    }

    // MARK: - Public API

    /// Returns the most recent log entries as formatted strings.
    /// Synchronous — safe to call from `ErrorReporting.capture()`.
    public func recentEntries(last: Int = 100) -> [String] {
        ringBuffer.entries(last: last).map { $0.formatted() }
    }

    /// Concatenates all log files into a single `.log` for sharing.
    /// Streams data through FileHandle to avoid loading all files into memory.
    ///
    /// This is a deliberate user action ("Send Logs"), so surfacing
    /// errors via `throws` is appropriate.
    private static let exportChunkSize = 64 * 1024 // 64KB

    public func exportLogs() async throws -> URL {
        // Flush buffered entries and await the write to complete on the actor
        await fileBuffer.flush()

        let logFiles = await fileWriter.logFileURLs()

        guard !logFiles.isEmpty else {
            throw LogExportError.noLogsAvailable
        }

        let tempDir = FileManager.default.temporaryDirectory
        let logURL = tempDir.appendingPathComponent("flipcash-logs-\(dateStamp()).log")

        // Remove any prior export
        try? FileManager.default.removeItem(at: logURL)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)

        // Stream through FileHandle in chunks to avoid loading all files into memory
        let outputHandle = try FileHandle(forWritingTo: logURL)
        defer { try? outputHandle.close() }

        for file in logFiles {
            guard let inputHandle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? inputHandle.close() }

            var chunk = try inputHandle.read(upToCount: Self.exportChunkSize) ?? Data()
            while !chunk.isEmpty {
                outputHandle.write(chunk)
                chunk = try inputHandle.read(upToCount: Self.exportChunkSize) ?? Data()
            }
        }

        return logURL
    }

    // MARK: - Private

    private static let exportFormatterLock = NSLock()
    private static let exportFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    private func dateStamp() -> String {
        Self.exportFormatterLock.lock()
        defer { Self.exportFormatterLock.unlock() }
        return Self.exportFormatter.string(from: Date())
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
