import Foundation
import Logging
import os

/// Single log handler that processes entries once and dispatches to
/// console, ring buffer, and file writer. Replaces MultiplexLogHandler
/// to avoid 3x entry construction and middleware processing per log call.
struct FlipcashLogHandler: LogHandler {

    var logLevel: Logging.Logger.Level
    var metadata: Logging.Logger.Metadata = [:]
    var metadataProvider: Logging.Logger.MetadataProvider?

    private let ringBuffer: RingBufferStorage
    private let fileBuffer: FileWriteBuffer
    private let middleware: [LogMiddleware]
    private static let osLogger = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.flipcash",
        category: "app"
    )

    init(
        logLevel: Logging.Logger.Level,
        ringBuffer: RingBufferStorage,
        fileBuffer: FileWriteBuffer,
        middleware: [LogMiddleware]
    ) {
        self.logLevel = logLevel
        self.ringBuffer = ringBuffer
        self.fileBuffer = fileBuffer
        self.middleware = middleware
    }

    subscript(metadataKey key: String) -> Logging.Logger.MetadataValue? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // Process once: construct entry, merge metadata, run middleware
        guard let entry = LogEntry.process(
            level: level, message: message, metadata: metadata,
            source: source, file: file, function: function, line: line,
            handlerMetadata: self.metadata, metadataProvider: metadataProvider,
            middleware: middleware
        ) else { return }

        // Format once for console + file
        let formatted = entry.formatted()

        // Console — OSLog for Console.app filtering and Instruments integration
        Self.osLogger.log(level: level.osLogType, "\(formatted, privacy: .public)")

        // Ring buffer — synchronous append under lock
        ringBuffer.append(entry)

        // File — batched, flushes every N entries
        fileBuffer.append(formatted + "\n")
    }
}

// MARK: - OSLog Level Mapping

private extension Logging.Logger.Level {
    var osLogType: OSLogType {
        switch self {
        case .trace:    .debug
        case .debug:    .debug
        case .info:     .info
        case .notice:   .default
        case .warning:  .default
        case .error:    .error
        case .critical: .fault
        }
    }
}
