import Foundation
import Logging

/// Prints formatted log entries to stdout, replacing the old `trace()` function.
///
/// Output format:
/// ```
/// [INFO] (10:32:15.1234) flipcash.rates-controller Rate fetched currency=USD
/// ```
public struct ConsoleLogHandler: LogHandler {

    public var logLevel: Logger.Level = .debug
    public var metadata: Logger.Metadata = [:]
    public var metadataProvider: Logger.MetadataProvider?

    private let middleware: [LogMiddleware]

    public init(middleware: [LogMiddleware] = []) {
        self.middleware = middleware
    }

    public subscript(metadataKey key: String) -> Logger.MetadataValue? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let merged = mergedMetadata(explicit: metadata)
        var entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: "\(message)",
            metadata: merged,
            source: source,
            function: function,
            file: file,
            line: line
        )

        for m in middleware {
            if !m.process(&entry) { return }
        }

        print(entry.formatted())
    }

    private func mergedMetadata(explicit: Logger.Metadata?) -> Logger.Metadata? {
        var merged = self.metadata
        if let provided = metadataProvider?.get() {
            merged.merge(provided) { _, new in new }
        }
        if let explicit {
            merged.merge(explicit) { _, new in new }
        }
        return merged.isEmpty ? nil : merged
    }
}
