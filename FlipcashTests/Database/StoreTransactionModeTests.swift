//
//  StoreTransactionModeTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing

/// Guards the store against DEFERRED transactions. One that reads before it writes fails with
/// SQLITE_BUSY at once, skipping the busy handler, while the notification extension holds the write
/// lock (Bugsnag 6a4fde3, 6ac1693). A write-first transaction loses nothing by beginning IMMEDIATE,
/// so every store transaction does.
@Suite("Store transaction mode")
struct StoreTransactionModeTests {

    private static let storeSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Database
        .deletingLastPathComponent() // FlipcashTests
        .deletingLastPathComponent() // repository root
        .appending(path: "FlipcashCore/Sources/FlipcashStore")

    @Test("every store transaction begins IMMEDIATE")
    func everyTransactionIsImmediate() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: Self.storeSources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        try #require(!files.isEmpty, "No store sources at \(Self.storeSources.path)")

        let transaction = /\.transaction\s*(\{|\()/
        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated()
            where line.contains(transaction) && !line.contains(".transaction(.immediate)") {
                offenders.append("\(file.lastPathComponent):\(index + 1)")
            }
        }
        #expect(offenders.isEmpty, "Use writer.transaction(.immediate): \(offenders)")
    }
}
