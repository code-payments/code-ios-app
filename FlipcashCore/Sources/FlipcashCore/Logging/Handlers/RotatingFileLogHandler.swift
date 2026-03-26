import Foundation
import Logging

/// Actor that manages rotating log files.
///
/// Writes to `app-0.log`, rotating to `app-1.log`, `app-2.log` when
/// the current file exceeds `maxFileSize`. Old files beyond `maxFileCount`
/// are deleted. All I/O errors are silently ignored.
public actor FileWriterActor {

    private let directory: URL
    private let maxFileSize: Int
    private let maxFileCount: Int
    private var currentFileIndex: Int = 0
    private var currentFileHandle: FileHandle?
    private var currentFileSize: Int = 0

    public init(directory: URL, maxFileSize: Int = 500_000, maxFileCount: Int = 3) {
        self.directory = directory
        self.maxFileSize = maxFileSize
        self.maxFileCount = maxFileCount
    }

    public func write(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        if currentFileHandle == nil {
            openCurrentFile()
        }

        if currentFileSize + data.count > maxFileSize {
            rotate()
        }

        currentFileHandle?.write(data)
        currentFileSize += data.count
    }

    public func logFileURLs() -> [URL] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "log" }
            .sorted { url1, url2 in
                let d1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 < d2
            }
    }

    // MARK: - Private

    private func fileURL(index: Int) -> URL {
        directory.appendingPathComponent("app-\(index).log")
    }

    private func openCurrentFile() {
        let url = fileURL(index: currentFileIndex)
        let fm = FileManager.default

        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }

        currentFileHandle = try? FileHandle(forWritingTo: url)
        currentFileHandle?.seekToEndOfFile()
        currentFileSize = Int(currentFileHandle?.offsetInFile ?? 0)
    }

    private func rotate() {
        currentFileHandle?.closeFile()
        currentFileHandle = nil
        currentFileIndex = (currentFileIndex + 1) % maxFileCount
        currentFileSize = 0

        // Truncate the file we're about to write to
        let url = fileURL(index: currentFileIndex)
        try? "".write(to: url, atomically: true, encoding: .utf8)

        openCurrentFile()
    }
}

/// LogHandler that dispatches writes to a `FileWriterActor`.
///
/// The `log()` call fires a detached task and returns immediately.
/// File I/O errors are silently ignored — the app never knows.
public struct RotatingFileLogHandler: LogHandler {

    private let fileWriter: FileWriterActor
    private let middleware: [LogMiddleware]

    public var logLevel: Logger.Level = .debug
    public var metadata: Logger.Metadata = [:]
    public var metadataProvider: Logger.MetadataProvider?

    public init(fileWriter: FileWriterActor, middleware: [LogMiddleware] = []) {
        self.fileWriter = fileWriter
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

        let formatted = entry.formatted() + "\n"
        let writer = fileWriter
        Task.detached {
            await writer.write(formatted)
        }
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
