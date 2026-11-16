//
//  BlobDownloadLinkTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import SwiftProtobuf
import FlipcashAPI
@testable import FlipcashCore

@Suite("Blob download link")
struct BlobDownloadLinkTests {

    @Test("A minted URL keeps the expiry the server gave it")
    func keepsExpiry() throws {
        let expiry = Date(timeIntervalSince1970: 1_800_000_300)
        let link = try #require(BlobDownloadLink(.with {
            $0.url = "https://cdn.example.invalid/photo?sig=1"
            $0.expiresAt = Google_Protobuf_Timestamp(date: expiry)
        }))
        #expect(link.url.absoluteString == "https://cdn.example.invalid/photo?sig=1")
        #expect(link.expiresAt == expiry)
    }

    @Test("A minted URL with no expiry has none, not 1970")
    func noExpiryIsNil() throws {
        let link = try #require(BlobDownloadLink(.with { $0.url = "https://cdn.example.invalid/photo" }))
        #expect(link.expiresAt == nil)
    }

    @Test("A URL that doesn't parse gives no link")
    func unparseableURLIsNil() {
        #expect(BlobDownloadLink(.with { $0.url = "" }) == nil)
    }

    @Test("A link minted from a blob record keeps the blob's size")
    func keepsSize() throws {
        let link = try #require(BlobDownloadLink(metadata: .with {
            $0.sizeBytes = 380_502
            $0.downloadURL = .with { $0.url = "https://cdn.example.invalid/photo?sig=1" }
        }))
        #expect(link.sizeBytes == 380_502)
        #expect(link.url.absoluteString == "https://cdn.example.invalid/photo?sig=1")
    }

    @Test("A blob record with no size gives a link of unknown size")
    func zeroSizeIsUnknown() throws {
        let link = try #require(BlobDownloadLink(metadata: .with {
            $0.downloadURL = .with { $0.url = "https://cdn.example.invalid/photo" }
        }))
        #expect(link.sizeBytes == nil)
    }

    @Test("A blob record with no download URL gives no link")
    func noURLIsNil() {
        #expect(BlobDownloadLink(metadata: .with { $0.sizeBytes = 10 }) == nil)
    }
}
