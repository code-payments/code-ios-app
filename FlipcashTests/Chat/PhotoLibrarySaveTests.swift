//
//  PhotoLibrarySaveTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashUI
@testable import Flipcash

@Suite("Photo save source")
@MainActor
struct PhotoLibrarySaveTests {

    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0])
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
    private static let heic = Data([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])
    private static let webp = Data([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])
    private static let gif = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0, 0, 0, 0, 0])

    private func save(original: Data?, failOriginal: Bool = false) async throws -> (data: [Data], images: Int) {
        var wroteData: [Data] = []
        var wroteImages = 0
        try await PhotoLibrary.save(
            image: UIImage(),
            original: original,
            writeOriginal: { data in
                if failOriginal { throw CocoaError(.fileWriteUnknown) }
                wroteData.append(data)
            },
            writeImage: { _ in wroteImages += 1 }
        )
        return (wroteData, wroteImages)
    }

    @Test("Original bytes are written untouched when present")
    func writesOriginal() async throws {
        let result = try await save(original: Self.png)
        #expect(result.data == [Self.png])
        #expect(result.images == 0)
    }

    @Test("The drawn image is written when no original is held")
    func fallsBackWhenMissing() async throws {
        let result = try await save(original: nil)
        #expect(result.data.isEmpty)
        #expect(result.images == 1)
    }

    @Test("Bytes that are not a library image fall back to the drawn image")
    func fallsBackWhenNotAnImage() async throws {
        let result = try await save(original: Data(repeating: 0x41, count: 32))
        #expect(result.data.isEmpty)
        #expect(result.images == 1)
    }

    @Test("A refused original falls back to the drawn image")
    func fallsBackWhenRefused() async throws {
        let result = try await save(original: Self.jpeg, failOriginal: true)
        #expect(result.images == 1)
    }

    @Test("Formats are recognised from their bytes")
    func detectsFormats() {
        for data in [Self.jpeg, Self.png, Self.heic, Self.webp, Self.gif] {
            #expect(ChatMediaImageSource.isLibraryImage(data))
        }
        #expect(!ChatMediaImageSource.isLibraryImage(Data([1, 2, 3])))
        #expect(!ChatMediaImageSource.isLibraryImage(Data(repeating: 0, count: 16)))
    }
}
