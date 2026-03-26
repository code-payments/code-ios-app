import Foundation
import Logging

/// Lock-protected circular buffer that stores the last N log entries.
///
/// The `log()` call appends under an `NSLock` and returns immediately.
/// `entries()` is also synchronous, making it safe to call from
/// `ErrorReporting.capture()` without async propagation.
public final class RingBufferStorage: @unchecked Sendable {

    private let lock = NSLock()
    private var buffer: [LogEntry?]
    private var writeIndex: Int = 0
    private var count: Int = 0
    private let capacity: Int

    public init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    public func append(_ entry: LogEntry) {
        lock.lock()
        defer { lock.unlock() }

        buffer[writeIndex] = entry
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    /// Returns entries in chronological order (oldest first).
    public func entries(last: Int? = nil) -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }

        guard count > 0 else { return [] }

        let requested = min(last ?? count, count)
        var result: [LogEntry] = []
        result.reserveCapacity(requested)

        // Start index is the oldest entry we want
        let startOffset = count - requested
        let oldestIndex = (writeIndex - count + capacity) % capacity

        for i in startOffset..<count {
            let index = (oldestIndex + i) % capacity
            if let entry = buffer[index] {
                result.append(entry)
            }
        }

        return result
    }
}

/// LogHandler that writes to a shared `RingBufferStorage`.
public struct RingBufferLogHandler: LogHandler {

    private let storage: RingBufferStorage
    private let middleware: [LogMiddleware]

    public var logLevel: Logger.Level = .debug
    public var metadata: Logger.Metadata = [:]
    public var metadataProvider: Logger.MetadataProvider?

    public init(storage: RingBufferStorage, middleware: [LogMiddleware] = []) {
        self.storage = storage
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

        storage.append(entry)
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
