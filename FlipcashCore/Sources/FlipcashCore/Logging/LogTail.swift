import Foundation

/// The last lines written to the rotating log files, read from disk.
public struct LogTail: Sendable, Equatable {

    /// Lines in the order they were written, oldest first, without trailing newlines.
    public let lines: [String]

    /// Modification date of the newest log file, or nil when there were no log files.
    public let lastWrite: Date?

    /// A tail with no lines and no files.
    public static let empty = LogTail(lines: [], lastWrite: nil)

    /// Creates a tail from lines already read and the newest file's modification date.
    public init(lines: [String], lastWrite: Date?) {
        self.lines = lines
        self.lastWrite = lastWrite
    }

    /// Reads up to `maxLines` of the most recent lines from the `.log` files in `directory`.
    ///
    /// Reads at most `maxBytesPerFile` from the end of each file, newest file first, and
    /// continues into older files only while fewer than `maxLines` lines have been found.
    public static func read(directory: URL, maxLines: Int, maxBytesPerFile: Int = 64 * 1024) -> LogTail {
        let files = logFilesNewestFirst(in: directory)
        guard let newest = files.first, maxLines > 0 else {
            return LogTail(lines: [], lastWrite: files.first?.date)
        }

        var lines: [String] = []
        for file in files {
            lines = tailLines(of: file.url, maxBytes: maxBytesPerFile) + lines
            if lines.count >= maxLines { break }
        }

        return LogTail(lines: Array(lines.suffix(maxLines)), lastWrite: newest.date)
    }

    // MARK: - Private

    private static func logFilesNewestFirst(in directory: URL) -> [(url: URL, date: Date)] {
        let key = URLResourceKey.contentModificationDateKey
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [key]) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "log" }
            .map { url in
                (url, (try? url.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast)
            }
            .sorted { $0.date > $1.date }
    }

    /// Complete lines in the last `maxBytes` of the file; a line cut by the read window is dropped.
    private static func tailLines(of url: URL, maxBytes: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return [] }
        // Starts one byte early so the first split element is "" when the window
        // begins on a line boundary, and the cut-off line otherwise; either way it goes.
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) - 1 : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(),
              !data.isEmpty else {
            return []
        }

        var lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if offset > 0, !lines.isEmpty {
            lines.removeFirst()
        }
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}
