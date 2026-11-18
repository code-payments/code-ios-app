//
//  ChatMediaLoadReportTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI
import Kingfisher

@Suite("Chat photo load report")
@MainActor
struct ChatMediaLoadReportTests {

    private let folder: TemporaryCacheFolder
    private let caches: ChatMediaCaches

    init() throws {
        let folder = TemporaryCacheFolder()
        self.folder = folder
        caches = try folder.chatMediaCaches()
    }

    private static let blobID = BlobID(data: Data([1]))
    private static let signedURL = URL(string: "https://d1.cloudfront.net/blob/abc?Expires=1700000000&Signature=SECRETSIG&Key-Pair-Id=KPID")!

    private static func response(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: signedURL, statusCode: status, httpVersion: "HTTP/2", headerFields: headers)!
    }

    private static func success(cacheType: CacheType, source: Source) -> Result<RetrieveImageResult, KingfisherError> {
        .success(RetrieveImageResult(image: UIImage(), cacheType: cacheType, source: source, originalSource: source, data: { nil }))
    }

    private func sealedProvider() -> DecryptingProvider {
        DecryptingProvider(cacheKey: "chat-media-test", url: Self.signedURL, decrypt: { $0 }, caches: caches)
    }

    @Test("A transfer splits time to first byte from the body, and keeps the CDN edge and cache headers")
    func transferTimingsAndHeaders() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let transfer = ChatMediaTransfer(
            fetchStart: start,
            responseStart: start.addingTimeInterval(0.25),
            responseEnd: start.addingTimeInterval(1.75),
            response: Self.response(status: 200, headers: ["X-Cache": "Miss from cloudfront", "X-Amz-Cf-Pop": "ORD58-P16"])
        )

        #expect(transfer.firstByte == .milliseconds(250))
        #expect(transfer.body == .milliseconds(1500))
        #expect(transfer.status == 200)
        #expect(transfer.xCache == "Miss from cloudfront")
        #expect(transfer.pop == "ORD58-P16")
    }

    @Test("A plaintext photo from the network reports a network load of its original rendition")
    func plaintextNetworkLoad() {
        let source = Source.network(KF.ImageResource(downloadURL: Self.signedURL, cacheKey: "chat-media-test"))
        let metadata = ChatMediaLoadReport(Self.success(cacheType: .none, source: source), blobID: Self.blobID, surface: .bubble, sealed: false).metadata

        #expect(metadata["outcome"] == "ok")
        #expect(metadata["cache"] == "network")
        #expect(metadata["sealed"] == "false")
        #expect(metadata["rendition"] == "original")
        #expect(metadata["surface"] == "bubble")
        #expect(metadata["blobId"] == "\(Self.blobID)")
    }

    @Test("An encrypted photo reports the transfer and decrypt time its provider recorded")
    func sealedLoadReportsTrace() {
        let provider = sealedProvider()
        var transfer = ChatMediaTransfer()
        transfer.firstByte = .milliseconds(300)
        transfer.record(Self.response(status: 200, headers: ["X-Amz-Cf-Pop": "ORD58-P16"]))
        provider.trace.update {
            $0.transfer = transfer
            $0.decrypt = .milliseconds(12)
        }

        let metadata = ChatMediaLoadReport(Self.success(cacheType: .none, source: .provider(provider)), blobID: Self.blobID, surface: .viewer, sealed: true).metadata

        #expect(metadata["sealed"] == "true")
        #expect(metadata["firstByteMs"] == "300")
        #expect(metadata["decryptMs"] == "12")
        #expect(metadata["pop"] == "ORD58-P16")
    }

    @Test("A failed load names its step, and its status or error code")
    func failureSteps() {
        let expired = ChatMediaLoadReport(
            .failure(.responseError(reason: .invalidHTTPStatusCode(response: Self.response(status: 403, headers: ["X-Cache": "Error from cloudfront"])))),
            blobID: Self.blobID,
            surface: .bubble,
            sealed: false
        )
        #expect(expired.outcome == .failed(.fetch))
        #expect(expired.metadata["status"] == "403")
        #expect(expired.metadata["xCache"] == "Error from cloudfront")

        let timedOut = ChatMediaLoadReport(
            .failure(.responseError(reason: .URLSessionError(error: URLError(.timedOut)))),
            blobID: Self.blobID,
            surface: .bubble,
            sealed: false
        )
        #expect(timedOut.outcome == .failed(.fetch))
        #expect(timedOut.errorDomain == NSURLErrorDomain)
        #expect(timedOut.errorCode == URLError.timedOut.rawValue)

        let provider = sealedProvider()
        provider.trace.update { $0.step = .decrypt }
        let undecryptable = ChatMediaLoadReport(
            .failure(.imageSettingError(reason: .dataProviderError(provider: provider, error: BlobOpenFailure.authentication))),
            blobID: Self.blobID,
            surface: .bubble,
            sealed: true
        )
        #expect(undecryptable.outcome == .failed(.decrypt))
    }

    @Test("A cached photo Kingfisher downsampled from its full-size copy reports that copy, not the network")
    func fullSizeCopy() {
        // Kingfisher hands back a copy it processed from the full-size one as `.none`: it was not in
        // the cache under the bubble's processor. A photo drawn from the cache alone has no URL, so
        // it can't have come from the network.
        let source = Source.provider(CachedOnlyProvider(cacheKey: "chat-media-test"))
        let report = ChatMediaLoadReport(Self.success(cacheType: .none, source: source), blobID: Self.blobID, surface: .bubble, sealed: false)

        #expect(report.metadata["cache"] == "fullSize")
    }

    @Test("A load the view abandoned reports cancelled, not failed")
    func cancelledLoad() {
        let report = ChatMediaLoadReport(
            .failure(.imageSettingError(reason: .notCurrentSourceTask(result: nil, error: nil, source: .network(Self.signedURL)))),
            blobID: Self.blobID,
            surface: .bubble,
            sealed: false
        )

        #expect(report.outcome == .cancelled)
    }

    /// One load from `source` ending each way, named by how it ended. None of the failures carries
    /// the encrypted photo's provider, so none can say whether the photo was sealed.
    private static func outcomes(from source: Source) -> [(String, Result<RetrieveImageResult, KingfisherError>)] {
        [
            ("ok", success(cacheType: .disk, source: source)),
            ("cancelled", .failure(.imageSettingError(reason: .notCurrentSourceTask(result: nil, error: nil, source: source)))),
            ("fetch", .failure(.responseError(reason: .URLSessionError(error: URLError(.timedOut))))),
            ("process", .failure(.processorError(reason: .processingFailed(processor: DefaultImageProcessor.default, item: .data(Data()))))),
            ("cache", .failure(.cacheError(reason: .imageNotExisting(key: "chat-media-test")))),
        ]
    }

    @Test("A sealed photo reports sealed whether its load succeeds, fails or is cancelled")
    func sealedForEveryOutcome() {
        let locations: [(String, ChatMediaLocation)] = [
            ("download", ChatMediaLocation(url: Self.signedURL, caches: caches) { $0 }),
            ("cached", .cached(sealed: true, in: caches)),
        ]
        for (kind, location) in locations {
            let source = ChatMediaImageSource.source(blobID: Self.blobID, location: location)
            for (outcome, result) in Self.outcomes(from: source) {
                let report = ChatMediaLoadReport(result, blobID: Self.blobID, surface: .bubble, sealed: location.sealed)
                #expect(report.metadata["sealed"] == "true", "\(kind) \(outcome)")
            }
        }
    }

    @Test("A plaintext photo reports not sealed whether its load succeeds, fails or is cancelled")
    func plaintextForEveryOutcome() {
        let locations: [(String, ChatMediaLocation)] = [
            ("download", ChatMediaLocation(url: Self.signedURL, caches: caches)),
            ("cached", .cached(sealed: false, in: caches)),
        ]
        for (kind, location) in locations {
            let source = ChatMediaImageSource.source(blobID: Self.blobID, location: location)
            for (outcome, result) in Self.outcomes(from: source) {
                let report = ChatMediaLoadReport(result, blobID: Self.blobID, surface: .bubble, sealed: location.sealed)
                #expect(report.metadata["sealed"] == "false", "\(kind) \(outcome)")
            }
        }
    }

    @Test("No failure's report carries any part of the signed URL")
    func failureNeverLogsURL() {
        let failingURL = URLError(.timedOut, userInfo: [
            NSURLErrorFailingURLErrorKey: Self.signedURL,
            NSURLErrorFailingURLStringErrorKey: Self.signedURL.absoluteString,
        ])
        let provider = sealedProvider()
        provider.trace.update { state in
            var transfer = ChatMediaTransfer()
            transfer.record(Self.response(status: 403))
            state.transfer = transfer
        }
        let failures: [KingfisherError] = [
            .responseError(reason: .URLSessionError(error: failingURL)),
            .responseError(reason: .invalidHTTPStatusCode(response: Self.response(status: 403))),
            .imageSettingError(reason: .dataProviderError(provider: provider, error: ChatMediaHTTPError(status: 403))),
            .imageSettingError(reason: .dataProviderError(provider: provider, error: failingURL)),
            .requestError(reason: .invalidURL(request: URLRequest(url: Self.signedURL))),
        ]

        for failure in failures {
            let values = ChatMediaLoadReport(.failure(failure), blobID: Self.blobID, surface: .bubble, sealed: false).metadata.values.map(\.description)
            #expect(!values.contains { $0.contains("Signature") || $0.contains("cloudfront.net") || $0.contains("?") }, "\(failure.errorCode)")
        }
    }
}
