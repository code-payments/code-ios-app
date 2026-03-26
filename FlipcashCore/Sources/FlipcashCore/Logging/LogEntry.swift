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

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "(HH:mm:ss.SSSS)"
        return f
    }()

    public func formatted() -> String {
        let ts = Self.formatter.string(from: timestamp)
        let lvl = "[\(level.uppercased)]"
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
}

// MARK: - Logger.Level

extension Logger.Level {
    var uppercased: String {
        switch self {
        case .trace:    "TRACE"
        case .debug:    "DEBUG"
        case .info:     "INFO"
        case .notice:   "NOTICE"
        case .warning:  "WARNING"
        case .error:    "ERROR"
        case .critical: "CRITICAL"
        }
    }
}
