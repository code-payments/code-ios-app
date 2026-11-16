//
//  ChatPhotoPushPrefetcherTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Chat photo push prefetcher")
struct ChatPhotoPushPrefetcherTests {

    /// What the prefetcher asked of the network.
    private final class Spy: @unchecked Sendable {
        private let lock = NSLock()
        private var _mints: [BlobID] = []
        private var _downloads: [URL] = []
        private var _files: [URL] = []

        var mints: [BlobID] { lock.withLock { _mints } }
        var downloads: [URL] { lock.withLock { _downloads } }
        /// The files the stub download handed over.
        var files: [URL] { lock.withLock { _files } }

        func minted(_ blobID: BlobID) { lock.withLock { _mints.append(blobID) } }
        func downloaded(_ url: URL, into file: URL) {
            lock.withLock {
                _downloads.append(url)
                _files.append(file)
            }
        }
    }

    private let me = UUID()
    private let them = UUID()
    private static let wifi = ChatPhotoPrefetchNetwork(connected: true, constrained: false, expensive: false)
    private static let signedURL = URL(string: "https://cdn.example.com/blob?Signature=secret-signature")!

    /// A 1×1 PNG.
    private static let photoData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private func store() -> BlobCache {
        BlobCache(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("push-photos-\(UUID().uuidString)", isDirectory: true),
            limitBytes: 1 << 20
        )
    }

    private func blob(_ byte: UInt8) -> BlobID {
        BlobID(data: Data(repeating: byte, count: 16))
    }

    private var original: BlobID { blob(1) }
    private var display: BlobID { blob(2) }
    private var thumbnail: BlobID { blob(3) }

    private func attachment(sealed: SealedBlob? = nil) -> MediaAttachment {
        MediaAttachment(
            blobID: original, width: 3024, height: 4032, blurhash: nil, sealed: sealed,
            renditions: sealed == nil ? [
                MediaRendition(role: .display, blobID: display, width: 1080, height: 1440),
                MediaRendition(role: .thumbnail, blobID: thumbnail, width: 120, height: 160),
            ] : []
        )
    }

    private func sealedAttachment() -> MediaAttachment {
        attachment(sealed: SealedBlob(senderID: them, plaintextSize: Self.photoData.count))
    }

    private func message(_ attachment: MediaAttachment, from sender: UUID? = nil, redacted: Bool = false) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: 1), senderID: sender ?? them,
            content: .media([attachment], caption: nil),
            date: Date(timeIntervalSince1970: 1_700_000_000), unreadSeq: 1, eventSequence: 1,
            redacted: redacted
        )
    }

    private func prefetcher(
        _ spy: Spy,
        store: BlobCache,
        sizeBytes: Int64? = Int64(Self.photoData.count),
        status: Int = 200,
        body: Data = Self.photoData,
        plaintextLimit: Int64 = ChatPhotoPushPrefetcher.plaintextLimitBytes,
        sealedLimit: Int64 = ChatPhotoPushPrefetcher.sealedLimitBytes
    ) -> ChatPhotoPushPrefetcher {
        ChatPhotoPushPrefetcher(
            store: store,
            mint: { blobID in
                spy.minted(blobID)
                return BlobDownloadLink(url: Self.signedURL, sizeBytes: sizeBytes)
            },
            download: { url in
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString)")
                try body.write(to: file)
                spy.downloaded(url, into: file)
                let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (file, response, nil)
            },
            plaintextLimit: plaintextLimit,
            sealedLimit: sealedLimit
        )
    }

    private func prefetch(
        _ prefetcher: ChatPhotoPushPrefetcher,
        _ message: ConversationMessage,
        isGroup: Bool = false,
        muted: Bool = false,
        network: ChatPhotoPrefetchNetwork = Self.wifi,
        decrypt: ChatPhotoPushPrefetcher.Decrypt? = nil
    ) async -> ChatPhotoPrefetchReport? {
        await prefetcher.prefetch(
            message,
            selfUserID: me,
            isGroup: isGroup,
            muted: muted,
            network: network,
            rowWidth: 393,
            scale: 3,
            decrypt: { decrypt }
        )
    }

    // MARK: - Which copy -

    @Test("The push picks the copy the bubble draws: the smallest that covers the bubble")
    func picksBubbleCopy() {
        // 393 pt row × 0.78 × 3 = 920 px: the 1440 px DISPLAY covers it, the 160 px THUMBNAIL doesn't.
        #expect(ChatPhotoBubbleLayout.rendition(of: attachment(), rowWidth: 393, attributedIncoming: false, scale: 3)?.blobID == display)
        // 100 pt row × 0.78 × 1 = 78 px: the THUMBNAIL covers it.
        #expect(ChatPhotoBubbleLayout.rendition(of: attachment(), rowWidth: 100, attributedIncoming: false, scale: 1)?.blobID == thumbnail)
        // A member's bubble gives 32 pt to the avatar: (130 − 32) × 0.78 × 2 = 153 px fits the
        // THUMBNAIL; without the gutter it would be 203 px and need the DISPLAY.
        #expect(ChatPhotoBubbleLayout.rendition(of: attachment(), rowWidth: 130, attributedIncoming: true, scale: 2)?.blobID == thumbnail)
        #expect(ChatPhotoBubbleLayout.rendition(of: attachment(), rowWidth: 130, attributedIncoming: false, scale: 2)?.blobID == display)
    }

    @Test("A sealed photo's copy is its ORIGINAL, the blob its seal decrypts")
    func sealedPicksOriginal() {
        #expect(ChatPhotoBubbleLayout.rendition(of: sealedAttachment(), rowWidth: 393, attributedIncoming: false, scale: 3)?.role == .original)
    }

    // MARK: - Downloads -

    @Test("A plaintext photo lands in the store under its bubble copy's blob ID")
    func plaintextLandsUnderRendition() async throws {
        let spy = Spy()
        let store = store()

        let report = try #require(await prefetch(prefetcher(spy, store: store), message(attachment())))

        #expect(report.outcome == .downloaded)
        #expect(report.trigger == .push)
        #expect(report.rendition == .display)
        #expect(report.bytes == Self.photoData.count)
        #expect(spy.mints == [display])
        #expect(store.data(for: display) == Self.photoData)
        #expect(!store.holds(original))
        #expect(spy.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("A sealed photo lands decrypted, under its ORIGINAL's blob ID")
    func sealedLandsDecrypted() async throws {
        let spy = Spy()
        let store = store()
        let ciphertext = Data("ciphertext".utf8)
        let prefetcher = prefetcher(spy, store: store, sizeBytes: Int64(ciphertext.count), body: ciphertext)

        let report = try #require(await prefetch(prefetcher, message(sealedAttachment()), decrypt: { blob, _, _ in
            #expect(blob == ciphertext)
            return Self.photoData
        }))

        #expect(report.outcome == .downloaded)
        #expect(report.sealed)
        #expect(report.rendition == .original)
        #expect(report.decrypt != nil)
        #expect(store.data(for: original) == Self.photoData)
        #expect(spy.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    // MARK: - Skips -

    @Test("A sealed photo whose chat key can't be opened here is skipped before the mint")
    func sealedWithoutKeySkips() async throws {
        let spy = Spy()

        let report = try #require(await prefetch(prefetcher(spy, store: store()), message(sealedAttachment()), decrypt: nil))

        #expect(report.outcome == .skipped(.keyPending))
        #expect(spy.mints.isEmpty)
    }

    @Test("A photo the store holds, as its bubble copy or its ORIGINAL, is skipped")
    func storedPhotoSkips() async throws {
        for held in [display, original] {
            let spy = Spy()
            let store = store()
            store.write(Self.photoData, for: held)

            let report = try #require(await prefetch(prefetcher(spy, store: store), message(attachment())))

            #expect(report.outcome == .skipped(.policy(.cached)))
            #expect(spy.mints.isEmpty)
        }
    }

    @Test("The policy's skips reach the push: own, muted, redacted, offline, Low Data Mode")
    func policySkips() async throws {
        let offline = ChatPhotoPrefetchNetwork(connected: false, constrained: false, expensive: false)
        let lowData = ChatPhotoPrefetchNetwork(connected: true, constrained: true, expensive: false)
        let cases: [(ChatPhotoPrefetchSkip, ConversationMessage, Bool, ChatPhotoPrefetchNetwork)] = [
            (.own, message(attachment(), from: me), false, Self.wifi),
            (.muted, message(attachment()), true, Self.wifi),
            (.redacted, message(attachment(), redacted: true), false, Self.wifi),
            (.offline, message(attachment()), false, offline),
            (.lowDataMode, message(attachment()), false, lowData),
        ]
        for (skip, message, muted, network) in cases {
            let spy = Spy()

            let report = try #require(await prefetch(prefetcher(spy, store: store()), message, muted: muted, network: network))

            #expect(report.outcome == .skipped(.policy(skip)))
            #expect(spy.mints.isEmpty)
        }
    }

    @Test("A copy whose size the server doesn't send is skipped without downloading")
    func unknownSizeSkips() async throws {
        let spy = Spy()

        let report = try #require(await prefetch(prefetcher(spy, store: store(), sizeBytes: nil), message(attachment())))

        #expect(report.outcome == .skipped(.noSize))
        #expect(spy.downloads.isEmpty)
    }

    @Test("A copy over its kind's limit is skipped without downloading; sealed copies have the lower limit")
    func oversizedSkips() async throws {
        let size = ChatPhotoPushPrefetcher.sealedLimitBytes + 1
        #expect(size <= ChatPhotoPushPrefetcher.plaintextLimitBytes)

        let sealedSpy = Spy()
        let sealed = try #require(await prefetch(
            prefetcher(sealedSpy, store: store(), sizeBytes: size), message(sealedAttachment()), decrypt: { _, _, _ in Self.photoData }
        ))
        #expect(sealed.outcome == .skipped(.tooLarge))
        #expect(sealedSpy.downloads.isEmpty)

        let plainSpy = Spy()
        let tooLarge = ChatPhotoPushPrefetcher.plaintextLimitBytes + 1
        let plain = try #require(await prefetch(prefetcher(plainSpy, store: store(), sizeBytes: tooLarge), message(attachment())))
        #expect(plain.outcome == .skipped(.tooLarge))
        #expect(plainSpy.downloads.isEmpty)
    }

    @Test("A body larger than the limit, whatever the server said, is dropped")
    func oversizedBodyDropped() async throws {
        let spy = Spy()
        let store = store()
        let prefetcher = prefetcher(spy, store: store, sizeBytes: 10, plaintextLimit: Int64(Self.photoData.count - 1))

        let report = try #require(await prefetch(prefetcher, message(attachment())))

        #expect(report.outcome == .skipped(.tooLarge))
        #expect(!store.holds(display))
        #expect(spy.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    // MARK: - Failures -

    @Test("An HTTP error leaves nothing in the store and logs the status")
    func httpErrorLeavesNothing() async throws {
        let spy = Spy()
        let store = store()

        let report = try #require(await prefetch(prefetcher(spy, store: store, status: 403), message(attachment())))

        #expect(report.outcome == .failed(.fetch))
        #expect(report.transfer?.status == 403)
        #expect(!store.holds(display))
        #expect(spy.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("A body that isn't an image leaves nothing in the store")
    func notAnImageLeavesNothing() async throws {
        let spy = Spy()
        let store = store()

        let report = try #require(await prefetch(prefetcher(spy, store: store, body: Data("<html>".utf8)), message(attachment())))

        #expect(report.outcome == .failed(.decode))
        #expect(!store.holds(display))
    }

    @Test("A sealed photo that fails to open leaves nothing in the store")
    func decryptFailureLeavesNothing() async throws {
        let spy = Spy()
        let store = store()
        struct Broken: Error {}

        let report = try #require(await prefetch(prefetcher(spy, store: store), message(sealedAttachment()), decrypt: { _, _, _ in
            throw Broken()
        }))

        #expect(report.outcome == .failed(.decrypt))
        #expect(!store.holds(original))
    }

    @Test("The log line carries no URL or signature")
    func logCarriesNoURL() async throws {
        let report = try #require(await prefetch(prefetcher(Spy(), store: store()), message(attachment())))

        let logged = report.metadata.values.map { "\($0)" }.joined(separator: " ")
        #expect(!logged.contains("cdn.example.com"))
        #expect(!logged.contains("Signature"))
        #expect(report.metadata["trigger"] == "push")
    }
}
