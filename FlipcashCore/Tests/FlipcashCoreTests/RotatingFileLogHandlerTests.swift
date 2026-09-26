import Foundation
import Testing
@testable import FlipcashCore

@Suite("FileWriterActor Tests")
struct RotatingFileLogHandlerTests {

    @Test("Writes entries to the current log file")
    func writesToFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = FileWriterActor(directory: dir, maxFileSize: 1024, maxFileCount: 3)
        await writer.write("[INFO] test message 1\n")
        await writer.write("[INFO] test message 2\n")

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(files.count == 1)

        let content = try String(contentsOf: files[0], encoding: .utf8)
        #expect(content.contains("test message 1"))
        #expect(content.contains("test message 2"))
    }

    @Test("Rotates when file exceeds max size")
    func rotatesFiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Very small max size to force rotation
        let writer = FileWriterActor(directory: dir, maxFileSize: 50, maxFileCount: 3)

        // Write enough to trigger rotation
        for i in 0..<10 {
            await writer.write("[INFO] message number \(i) with some padding text\n")
        }

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(files.count >= 2)
        #expect(files.count <= 3)
    }

    @Test("Collects all log file URLs")
    func collectsLogFileURLs() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = FileWriterActor(directory: dir, maxFileSize: 50, maxFileCount: 3)
        for i in 0..<10 {
            await writer.write("[INFO] message \(i) padding text here\n")
        }

        let urls = await writer.logFileURLs()
        #expect(!urls.isEmpty)
        for url in urls {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("A second launch resumes at the most recently modified file instead of index 0")
    func resumesAtMostRecentFileAcrossLaunches() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let maxFileSize = 50

        // Launch 1: two lines are enough to fill app-0.log and roll into app-1.log.
        let writerA = FileWriterActor(directory: dir, maxFileSize: maxFileSize, maxFileCount: 3)
        await writerA.write("[A] line 0 with padding text here\n")
        await writerA.write("[A] line 1 with padding text here\n")

        let secondFileURL = dir.appendingPathComponent("app-1.log")
        let secondFileContentAfterA = try String(contentsOf: secondFileURL, encoding: .utf8)
        #expect(secondFileContentAfterA.contains("[A] line 1"), "Launch 1 should have rotated into app-1.log")

        // Launch 2: a brand-new writer instance over the same directory (as happens on app relaunch).
        let writerB = FileWriterActor(directory: dir, maxFileSize: maxFileSize, maxFileCount: 3)
        await writerB.write("[B] launch 2 line\n")

        // Launch 1's lines in the second file must survive launch 2's first write.
        let secondFileContentAfterB = try String(contentsOf: secondFileURL, encoding: .utf8)
        #expect(
            secondFileContentAfterB.contains("[A] line 1"),
            "Launch 1's content in app-1.log was destroyed by launch 2 starting over at app-0.log"
        )

        // The exported/concatenated log (files in the order the export path reads them)
        // must contain both sessions, in chronological order.
        let orderedURLs = await writerB.logFileURLs()
        let concatenated = try orderedURLs.map { try String(contentsOf: $0, encoding: .utf8) }.joined()

        let rangeOfLine0 = concatenated.range(of: "[A] line 0")
        let rangeOfLine1 = concatenated.range(of: "[A] line 1")
        let rangeOfB = concatenated.range(of: "[B] launch 2 line")

        #expect(rangeOfLine0 != nil)
        #expect(rangeOfLine1 != nil, "Launch 1's second file is missing from the exported log")
        #expect(rangeOfB != nil)

        if let rangeOfLine0, let rangeOfLine1, let rangeOfB {
            #expect(rangeOfLine0.upperBound <= rangeOfLine1.lowerBound)
            #expect(rangeOfLine1.upperBound <= rangeOfB.lowerBound, "Launch 2's line must come after launch 1's in the exported log")
        }
    }
}
