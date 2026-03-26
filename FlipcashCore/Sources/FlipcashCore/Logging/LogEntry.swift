import Foundation
import Logging

public struct LogEntry: Sendable {

    public let timestamp: Date
    public let level: Logger.Level
    public var message: String
    public var metadata: Logger.Metadata?
    public let source: String
    public let function: String
    public let file: String
    public let line: UInt

    public init(
        timestamp: Date,
        level: Logger.Level,
        message: String,
        metadata: Logger.Metadata?,
        source: String,
        function: String,
        file: String,
        line: UInt
    ) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.metadata = metadata
        self.source = source
        self.function = function
        self.file = file
        self.line = line
    }

    // MARK: - Formatting

    // NSLock protects the shared DateFormatter (which is not thread-safe)
    private static let formatterLock = NSLock()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "(HH:mm:ss.SSSS)"
        return f
    }()

    private static func formatTimestamp(_ date: Date) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return formatter.string(from: date)
    }

    public func formatted() -> String {
        let ts = Self.formatTimestamp(timestamp)
        let lvl = "[\(level.rawValue.uppercased())]"
        var result = "\(lvl) \(ts) \(source) \(message)"

        if let metadata, !metadata.isEmpty {
            let pairs = metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            result += " \(pairs)"
        }

        return result
    }

    /// Creates a `LogEntry` from handler parameters, merges metadata, and runs the middleware pipeline.
    /// Returns `nil` if any middleware drops the entry.
    static func process(
        level: Logger.Level,
        message: Logger.Message,
        metadata explicitMetadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt,
        handlerMetadata: Logger.Metadata,
        metadataProvider: Logger.MetadataProvider?,
        middleware: [LogMiddleware]
    ) -> LogEntry? {
        var merged = handlerMetadata
        if let provided = metadataProvider?.get() {
            merged.merge(provided) { _, new in new }
        }
        if let explicitMetadata {
            merged.merge(explicitMetadata) { _, new in new }
        }

        var entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: "\(message)",
            metadata: merged.isEmpty ? nil : merged,
            source: source,
            function: function,
            file: file,
            line: line
        )

        for m in middleware {
            if !m.process(&entry) { return nil }
        }

        return entry
    }
}

