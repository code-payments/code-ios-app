//
//  ChatPhotoSendProgressTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import FlipcashCore
@testable import FlipcashUI

@Suite("Chat photo send progress")
@MainActor
struct ChatPhotoSendProgressTests {

    private func bytes(_ sent: Int64, of total: Int64) -> BlobUploadProgress {
        BlobUploadProgress(sentBytes: sent, totalBytes: total)
    }

    @Test("Bytes sent map to the share of the body, clamped, and nil for an unknown length")
    func bytesToFraction() {
        #expect(bytes(0, of: 200).fraction == 0)
        #expect(bytes(50, of: 200).fraction == 0.25)
        #expect(bytes(200, of: 200).fraction == 1)
        #expect(bytes(300, of: 200).fraction == 1)
        #expect(bytes(10, of: 0).fraction == nil)
        #expect(bytes(10, of: -1).fraction == nil)
    }

    @Test("A send runs preparing, uploading, processing, sending, sent")
    func happyPath() {
        let progress = ChatPhotoSendProgress()
        #expect(progress.phase == .preparing)
        #expect(progress.showsOverlay)

        progress.didUpload(bytes(25, of: 100))
        #expect(progress.phase == .uploading(fraction: 0.25))

        progress.didUpload(bytes(100, of: 100))
        #expect(progress.phase == .uploading(fraction: 1))

        progress.beginProcessing()
        #expect(progress.phase == .processing)
        #expect(progress.showsOverlay)

        progress.beginSending()
        #expect(progress.phase == .sending)
        #expect(progress.showsOverlay)

        progress.finish()
        #expect(progress.phase == .sent)
        #expect(!progress.showsOverlay)
    }

    @Test("The bar never runs backwards within an attempt")
    func monotonicWithinAttempt() {
        let progress = ChatPhotoSendProgress()
        progress.didUpload(bytes(60, of: 100))
        progress.didUpload(bytes(40, of: 100))
        #expect(progress.phase == .uploading(fraction: 0.6))
    }

    @Test("A byte count that lands after the upload moved on is ignored")
    func lateBytesIgnored() {
        let progress = ChatPhotoSendProgress()
        progress.beginProcessing()
        progress.didUpload(bytes(50, of: 100))
        #expect(progress.phase == .processing)

        progress.fail()
        progress.didUpload(bytes(50, of: 100))
        #expect(progress.phase == .failed)
    }

    @Test("A byte count with no known length leaves the phase alone")
    func unknownLengthIgnored() {
        let progress = ChatPhotoSendProgress()
        progress.didUpload(bytes(50, of: 0))
        #expect(progress.phase == .preparing)
    }

    @Test("A failure hides the overlay; a new attempt brings it back from the start", arguments: [
        ChatPhotoSendProgress.Phase.preparing, .uploading(fraction: 0.5), .processing, .sending,
    ])
    func failureThenRetry(from phase: ChatPhotoSendProgress.Phase) {
        let progress = ChatPhotoSendProgress()
        switch phase {
        case .preparing: break
        case .uploading(let fraction): progress.didUpload(bytes(Int64(fraction * 100), of: 100))
        case .processing: progress.beginProcessing()
        case .sending: progress.beginSending()
        case .sent, .failed: Issue.record("not a starting phase")
        }
        #expect(progress.phase == phase)

        progress.fail()
        #expect(progress.phase == .failed)
        #expect(!progress.showsOverlay)

        progress.beginAttempt()
        #expect(progress.phase == .preparing)
        #expect(progress.showsOverlay)
    }

    @Test("A retried store starts the bar over")
    func retriedStoreResets() {
        let progress = ChatPhotoSendProgress()
        progress.didUpload(bytes(80, of: 100))
        progress.beginAttempt()
        progress.didUpload(bytes(10, of: 100))
        #expect(progress.phase == .uploading(fraction: 0.1))
    }
}
