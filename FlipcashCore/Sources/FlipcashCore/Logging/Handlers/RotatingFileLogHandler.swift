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
    private var fatalFailure: Bool = false
    private var hasResumed: Bool = false

    public init(directory: URL, maxFileSize: Int = 500_000, maxFileCount: Int = 3) {
        self.directory = directory
        self.maxFileSize = maxFileSize
        self.maxFileCount = maxFileCount
    }

    public func write(_ line: String) {
        guard !fatalFailure, let data = line.data(using: .utf8) else { return }

        if currentFileHandle == nil {
            openCurrentFile()
        }

        if currentFileSize + data.count > maxFileSize {
            rotate()
        }

        do {
            try currentFileHandle?.write(contentsOf: data)
            currentFileSize += data.count
        } catch {
            fatalFailure = true
        }
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
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        if !hasResumed {
            hasResumed = true
            currentFileIndex = mostRecentlyModifiedFileIndex() ?? currentFileIndex
        }

        let url = fileURL(index: currentFileIndex)

        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else {
            fatalFailure = true
            return
        }
        currentFileHandle = handle
        currentFileSize = Int((try? handle.seekToEnd()) ?? 0)
    }

    /// Finds the index of the most recently modified `app-N.log` on disk, so a new
    /// launch resumes writing where the previous one left off instead of restarting
    /// at `app-0.log` (which would immediately rotate away and truncate whichever
    /// file the previous session was actually still writing to).
    private func mostRecentlyModifiedFileIndex() -> Int? {
        let fm = FileManager.default
        var bestIndex: Int?
        var bestDate = Date.distantPast

        for index in 0..<maxFileCount {
            let url = fileURL(index: index)
            guard fm.fileExists(atPath: url.path) else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if bestIndex == nil || date > bestDate {
                bestIndex = index
                bestDate = date
            }
        }

        return bestIndex
    }

    private func rotate() {
        try? currentFileHandle?.close()
        currentFileHandle = nil
        currentFileIndex = (currentFileIndex + 1) % maxFileCount
        currentFileSize = 0

        // Truncate the file we're about to write to. If we can't, we'd
        // append to stale rotated content — bail instead.
        let url = fileURL(index: currentFileIndex)
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            fatalFailure = true
            return
        }

        openCurrentFile()
    }
}

/// Batches formatted log lines and flushes them to the `FileWriterActor`
/// in a single `Task.detached` per batch, reducing task allocation overhead.
public final class FileWriteBuffer: @unchecked Sendable {

    private let lock = NSLock()
    private var buffer: [String] = []
    private let writer: FileWriterActor
    private let flushThreshold: Int

    public init(writer: FileWriterActor, flushThreshold: Int = 10) {
        self.writer = writer
        self.flushThreshold = flushThreshold
    }

    /// - Parameter forceFlush: Bypasses the batch threshold and flushes immediately.
    ///   Used for `.warning` and above, so a force-quit only risks losing sub-warning
    ///   lines rather than up to `flushThreshold - 1` of any severity.
    public func append(_ line: String, forceFlush: Bool = false) {
        lock.lock()
        buffer.append(line)
        let shouldFlush = forceFlush || buffer.count >= flushThreshold
        let batch: String? = shouldFlush ? buffer.joined() : nil
        if shouldFlush { buffer = [] }
        lock.unlock()

        if let batch {
            let writer = self.writer
            Task.detached {
                await writer.write(batch)
            }
        }
    }

    /// Flushes any remaining buffered lines to disk and waits for the write to complete.
    public func flush() async {
        let remaining = drainBuffer()
        guard !remaining.isEmpty else { return }
        await writer.write(remaining)
    }

    private func drainBuffer() -> String {
        lock.lock()
        defer { lock.unlock() }
        let joined = buffer.joined()
        buffer = []
        return joined
    }
}
