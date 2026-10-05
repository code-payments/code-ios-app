import Foundation
import Testing
@testable import FlipcashCore

@Suite("LogTail")
struct LogTailTests {

    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func write(_ contents: String, to name: String, modified: Date) throws {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    private func lines(_ range: ClosedRange<Int>, prefix: String = "line") -> String {
        range.map { "\(prefix) \($0)\n" }.joined()
    }

    @Test("A missing directory gives an empty tail")
    func missingDirectory() {
        let tail = LogTail.read(directory: directory.appendingPathComponent("absent"), maxLines: 10)
        #expect(tail == .empty)
    }

    @Test("An empty directory gives an empty tail")
    func emptyDirectory() {
        #expect(LogTail.read(directory: directory, maxLines: 10) == .empty)
    }

    @Test("A file shorter than the limit is returned whole, with its modification date")
    func shortFile() throws {
        let modified = Date(timeIntervalSince1970: 1_800_000_000)
        try write(lines(1...3), to: "app-0.log", modified: modified)

        let tail = LogTail.read(directory: directory, maxLines: 10)

        #expect(tail.lines == ["line 1", "line 2", "line 3"])
        #expect(tail.lastWrite == modified)
    }

    @Test("A file longer than the limit gives its last lines, oldest first")
    func longFile() throws {
        try write(lines(1...20), to: "app-0.log", modified: Date())

        let tail = LogTail.read(directory: directory, maxLines: 3)

        #expect(tail.lines == ["line 18", "line 19", "line 20"])
    }

    @Test("A final line without a newline is kept")
    func unterminatedLastLine() throws {
        try write("line 1\nline 2", to: "app-0.log", modified: Date())

        #expect(LogTail.read(directory: directory, maxLines: 10).lines == ["line 1", "line 2"])
    }

    @Test("A line cut by the read window is dropped")
    func partialFirstLineDropped() throws {
        // 20 bytes from the end of "aaaaaaaaaa\nbbbbbbbbbb\ncccccccccc\n" starts inside the b line.
        try write("aaaaaaaaaa\nbbbbbbbbbb\ncccccccccc\n", to: "app-0.log", modified: Date())

        let tail = LogTail.read(directory: directory, maxLines: 10, maxBytesPerFile: 20)

        #expect(tail.lines == ["cccccccccc"])
    }

    @Test("A read window that starts on a line boundary keeps that line")
    func windowOnLineBoundary() throws {
        // The last 22 bytes are exactly "bbbbbbbbbb\ncccccccccc\n".
        try write("aaaaaaaaaa\nbbbbbbbbbb\ncccccccccc\n", to: "app-0.log", modified: Date())

        let tail = LogTail.read(directory: directory, maxLines: 10, maxBytesPerFile: 22)

        #expect(tail.lines == ["bbbbbbbbbb", "cccccccccc"])
    }

    @Test("A tail continues into the previous rotated file when the newest is short")
    func spansRotatedFiles() throws {
        let older = Date(timeIntervalSince1970: 1_800_000_000)
        let newer = older.addingTimeInterval(60)
        try write(lines(1...5, prefix: "old"), to: "app-1.log", modified: older)
        try write(lines(1...2, prefix: "new"), to: "app-2.log", modified: newer)

        let tail = LogTail.read(directory: directory, maxLines: 4)

        #expect(tail.lines == ["old 4", "old 5", "new 1", "new 2"])
        #expect(tail.lastWrite == newer)
    }

    @Test("Files other than .log are ignored")
    func ignoresOtherFiles() throws {
        try write("not a log\n", to: "notes.txt", modified: Date())
        try write("line 1\n", to: "app-0.log", modified: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(LogTail.read(directory: directory, maxLines: 10).lines == ["line 1"])
    }
}
