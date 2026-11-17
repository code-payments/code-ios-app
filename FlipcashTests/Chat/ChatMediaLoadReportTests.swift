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

    private static let blobID = BlobID(data: Data([1]))
    private static let signedURL = URL(string: "https://d1.cloudfront.net/blob/abc?Expires=1700000000&Signature=SECRETSIG&Key-Pair-Id=KPID")!

    private static func response(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: signedURL, statusCode: status, httpVersion: "HTTP/2", headerFields: headers)!
    }

    private static func success(cacheType: CacheType, source: Source) -> Result<RetrieveImageResult, KingfisherError> {
        .success(RetrieveImageResult(image: UIImage(), cacheType: cacheType, source: source, originalSource: source, data: { nil }))
    }

    private static func sealedProvider() -> DecryptingProvider {
        DecryptingProvider(cacheKey: "chat-media-test", url: signedURL, decrypt: { $0 })
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
        let metadata = ChatMediaLoadReport(Self.success(cacheType: .none, source: source), blobID: Self.blobID, surface: .bubble).metadata

        #expect(metadata["outcome"] == "ok")
        #expect(metadata["cache"] == "network")
        #expect(metadata["sealed"] == "false")
        #expect(metadata["rendition"] == "original")
        #expect(metadata["surface"] == "bubble")
        #expect(metadata["blobId"] == "\(Self.blobID)")
    }

    @Test("An encrypted photo reports the transfer and decrypt time its provider recorded")
    func sealedLoadReportsTrace() {
        let provider = Self.sealedProvider()
        var transfer = ChatMediaTransfer()
        transfer.firstByte = .milliseconds(300)
        transfer.record(Self.response(status: 200, headers: ["X-Amz-Cf-Pop": "ORD58-P16"]))
        provider.trace.update {
            $0.transfer = transfer
            $0.decrypt = .milliseconds(12)
        }

        let metadata = ChatMediaLoadReport(Self.success(cacheType: .none, source: .provider(provider)), blobID: Self.blobID, surface: .viewer).metadata

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
            surface: .bubble
        )
        #expect(expired.outcome == .failed(.fetch))
        #expect(expired.metadata["status"] == "403")
        #expect(expired.metadata["xCache"] == "Error from cloudfront")

        let timedOut = ChatMediaLoadReport(
            .failure(.responseError(reason: .URLSessionError(error: URLError(.timedOut)))),
            blobID: Self.blobID,
            surface: .bubble
        )
        #expect(timedOut.outcome == .failed(.fetch))
        #expect(timedOut.errorDomain == NSURLErrorDomain)
        #expect(timedOut.errorCode == URLError.timedOut.rawValue)

        let provider = Self.sealedProvider()
        provider.trace.update { $0.step = .decrypt }
        let undecryptable = ChatMediaLoadReport(
            .failure(.imageSettingError(reason: .dataProviderError(provider: provider, error: BlobOpenFailure.authentication))),
            blobID: Self.blobID,
            surface: .bubble
        )
        #expect(undecryptable.outcome == .failed(.decrypt))
        #expect(undecryptable.sealed)
    }

    @Test("A load the view abandoned reports cancelled, not failed")
    func cancelledLoad() {
        let report = ChatMediaLoadReport(
            .failure(.imageSettingError(reason: .notCurrentSourceTask(result: nil, error: nil, source: .network(Self.signedURL)))),
            blobID: Self.blobID,
            surface: .bubble
        )

        #expect(report.outcome == .cancelled)
    }

    @Test("No failure's report carries any part of the signed URL")
    func failureNeverLogsURL() {
        let failingURL = URLError(.timedOut, userInfo: [
            NSURLErrorFailingURLErrorKey: Self.signedURL,
            NSURLErrorFailingURLStringErrorKey: Self.signedURL.absoluteString,
        ])
        let provider = Self.sealedProvider()
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
            let values = ChatMediaLoadReport(.failure(failure), blobID: Self.blobID, surface: .bubble).metadata.values.map(\.description)
            #expect(!values.contains { $0.contains("Signature") || $0.contains("cloudfront.net") || $0.contains("?") }, "\(failure.errorCode)")
        }
    }
}
