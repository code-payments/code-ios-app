import Foundation
import Logging

/// Single log handler that processes entries once and dispatches to
/// console, ring buffer, and file writer. Replaces MultiplexLogHandler
/// to avoid 3x entry construction and middleware processing per log call.
struct FlipcashLogHandler: LogHandler {

    var logLevel: Logger.Level
    var metadata: Logger.Metadata = [:]
    var metadataProvider: Logger.MetadataProvider?

    private let ringBuffer: RingBufferStorage
    private let fileBuffer: FileWriteBuffer
    private let middleware: [LogMiddleware]

    init(
        logLevel: Logger.Level,
        ringBuffer: RingBufferStorage,
        fileBuffer: FileWriteBuffer,
        middleware: [LogMiddleware]
    ) {
        self.logLevel = logLevel
        self.ringBuffer = ringBuffer
        self.fileBuffer = fileBuffer
        self.middleware = middleware
    }

    subscript(metadataKey key: String) -> Logger.MetadataValue? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
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

        // Console — synchronous print
        print(formatted)

        // Ring buffer — synchronous append under lock
        ringBuffer.append(entry)

        // File — batched, flushes every N entries
        fileBuffer.append(formatted + "\n")
    }
}
