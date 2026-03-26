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
}
