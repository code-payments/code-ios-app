//
//  ChatMediaLoadReport.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Synchronization
import FlipcashCore
import Kingfisher

nonisolated private let logger = Logger(label: "flipcash.chat-media")

/// Which view a chat photo load is for, as logged.
public enum ChatMediaSurface: String, Sendable {
    case bubble
    case viewer
    case quote
    case link
    case save
}

/// A CDN answer that was not a success, carrying its status so an expired link (403) can be told
/// from any other failure.
nonisolated struct ChatMediaHTTPError: Error, Equatable {
    let status: Int
}

/// The network half of one photo load: when its bytes arrived, how many, and which CDN edge sent them.
nonisolated struct ChatMediaTransfer: Equatable, Sendable {
    /// From the request starting to the first byte of the response.
    var firstByte: Duration?
    /// From the first byte of the response to the last.
    var body: Duration?
    var bytes: Int64?
    var status: Int?
    var reusedConnection: Bool?
    /// Where URLSession took the response from: `network`, `localCache`, `serverPush` or `unknown`.
    var fetchType: String?
    /// CloudFront's `X-Cache`: whether the edge held the object or went to the origin.
    var xCache: String?
    /// CloudFront's `X-Amz-Cf-Pop`: the edge location that answered.
    var pop: String?

    init() {}

    init(metrics: URLSessionTaskMetrics) {
        // The last transaction is the one that answered; any before it were redirects.
        guard let transaction = metrics.transactionMetrics.last else {
            self.init()
            return
        }
        self.init(
            fetchStart: transaction.fetchStartDate,
            responseStart: transaction.responseStartDate,
            responseEnd: transaction.responseEndDate,
            response: transaction.response as? HTTPURLResponse
        )
        bytes = transaction.countOfResponseBodyBytesReceived
        reusedConnection = transaction.isReusedConnection
        fetchType = Self.name(of: transaction.resourceFetchType)
    }

    init(fetchStart: Date?, responseStart: Date?, responseEnd: Date?, response: HTTPURLResponse?) {
        firstByte = Self.duration(from: fetchStart, to: responseStart)
        body = Self.duration(from: responseStart, to: responseEnd)
        if let response { record(response) }
    }

    /// Takes the status and the CDN's headers from `response`.
    mutating func record(_ response: HTTPURLResponse) {
        status = response.statusCode
        xCache = response.value(forHTTPHeaderField: "X-Cache")
        pop = response.value(forHTTPHeaderField: "X-Amz-Cf-Pop")
    }

    private static func duration(from start: Date?, to end: Date?) -> Duration? {
        guard let start, let end else { return nil }
        return .seconds(end.timeIntervalSince(start))
    }

    private static func name(of type: URLSessionTaskMetrics.ResourceFetchType) -> String {
        switch type {
        case .networkLoad: "network"
        case .localCache: "localCache"
        case .serverPush: "serverPush"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }
}

/// What an encrypted photo's fetch saw, read back when its load finishes. Kingfisher reports no
/// network metrics for a data provider, so the provider records its own through this delegate.
nonisolated final class ChatMediaLoadTrace: NSObject, URLSessionTaskDelegate, Sendable {

    struct State: Equatable, Sendable {
        /// The step running when the load stopped.
        var step: ChatMediaLoadReport.Step = .fetch
        var transfer: ChatMediaTransfer?
        var decrypt: Duration?
    }

    private let state = Mutex(State())

    var snapshot: State { state.withLock { $0 } }

    func update(_ body: (inout State) -> Void) {
        state.withLock { body(&$0) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let measured = ChatMediaTransfer(metrics: metrics)
        update { $0.transfer = measured }
    }
}

/// How one chat photo load went, logged when it finishes.
nonisolated struct ChatMediaLoadReport: Equatable {

    enum Step: String, Sendable {
        case fetch
        case decrypt
        case decode
        case process
        case cache
        case other
    }

    enum Outcome: Equatable {
        case ok
        /// The view moved on before the load finished.
        case cancelled
        case failed(Step)
    }

    let blobID: BlobID?
    let surface: ChatMediaSurface
    let outcome: Outcome
    /// Where the image came from on success; nil for a load that failed.
    var cache: CacheType?
    var sealed = false
    var transfer: ChatMediaTransfer?
    var decrypt: Duration?
    /// The failure's error domain and code. Never its description: a `URLError` or `KingfisherError`
    /// prints the failing URL, and with it the signature in its query.
    var errorDomain: String?
    var errorCode: Int?

    init(blobID: BlobID?, surface: ChatMediaSurface, outcome: Outcome) {
        self.blobID = blobID
        self.surface = surface
        self.outcome = outcome
    }

    init(_ result: Result<RetrieveImageResult, KingfisherError>, blobID: BlobID?, surface: ChatMediaSurface) {
        switch result {
        case .success(let value):
            self.init(blobID: blobID, surface: surface, outcome: .ok)
            cache = value.cacheType
            if case .provider(let provider) = value.source, let provider = provider as? DecryptingProvider {
                sealed = true
                let trace = provider.trace.snapshot
                transfer = trace.transfer
                decrypt = trace.decrypt
            } else {
                transfer = value.metrics.map { ChatMediaTransfer(metrics: $0.rawMetrics) }
            }
        case .failure(let error):
            self.init(error, blobID: blobID, surface: surface)
        }
    }

    private init(_ error: KingfisherError, blobID: BlobID?, surface: ChatMediaSurface) {
        var underlying: (any Error)?
        var response: HTTPURLResponse?
        var trace: ChatMediaLoadTrace.State?
        let outcome: Outcome
        switch error {
        case .requestError(reason: .taskCancelled):
            outcome = .cancelled
        case .requestError:
            outcome = .failed(.fetch)
        case .responseError(reason: .invalidHTTPStatusCode(let failed)):
            outcome = .failed(.fetch)
            response = failed
        case .responseError(reason: .URLSessionError(let failure)):
            outcome = .failed(.fetch)
            underlying = failure
        case .responseError:
            outcome = .failed(.fetch)
        case .imageSettingError(reason: .notCurrentSourceTask):
            outcome = .cancelled
        case .imageSettingError(reason: .dataProviderError(let provider, let failure)):
            trace = (provider as? DecryptingProvider)?.trace.snapshot
            outcome = .failed(trace?.step ?? .fetch)
            underlying = failure
        case .imageSettingError:
            outcome = .failed(.other)
        case .processorError:
            outcome = .failed(.process)
        case .cacheError:
            outcome = .failed(.cache)
        }

        self.init(blobID: blobID, surface: surface, outcome: outcome)
        sealed = trace != nil
        transfer = trace?.transfer
        decrypt = trace?.decrypt
        if let response {
            var recorded = transfer ?? ChatMediaTransfer()
            recorded.record(response)
            transfer = recorded
        }
        switch underlying {
        case is ChatMediaHTTPError:
            // The trace already holds the status and headers.
            break
        case let underlying?:
            let bridged = underlying as NSError
            errorDomain = bridged.domain
            errorCode = bridged.code
        case nil:
            errorDomain = "Kingfisher"
            errorCode = error.errorCode
        }
    }

    var metadata: Logger.Metadata {
        var metadata: Logger.Metadata = [
            "surface": "\(surface.rawValue)",
            // Every chat photo loads its ORIGINAL rendition.
            "rendition": "original",
            "sealed": "\(sealed)",
        ]
        if let blobID { metadata["blobId"] = "\(blobID)" }
        switch outcome {
        case .ok:
            metadata["outcome"] = "ok"
        case .cancelled:
            metadata["outcome"] = "cancelled"
        case .failed(let step):
            metadata["outcome"] = "failed"
            metadata["step"] = "\(step.rawValue)"
        }
        if let cache { metadata["cache"] = "\(Self.name(of: cache))" }
        if let transfer {
            if let firstByte = transfer.firstByte { metadata["firstByteMs"] = "\(Self.milliseconds(firstByte))" }
            if let body = transfer.body { metadata["bodyMs"] = "\(Self.milliseconds(body))" }
            if let bytes = transfer.bytes { metadata["bytes"] = "\(bytes)" }
            if let status = transfer.status { metadata["status"] = "\(status)" }
            if let reused = transfer.reusedConnection { metadata["reusedConnection"] = "\(reused)" }
            if let fetchType = transfer.fetchType { metadata["fetchType"] = "\(fetchType)" }
            if let xCache = transfer.xCache { metadata["xCache"] = "\(xCache)" }
            if let pop = transfer.pop { metadata["pop"] = "\(pop)" }
        }
        if let decrypt { metadata["decryptMs"] = "\(Self.milliseconds(decrypt))" }
        if let errorDomain { metadata["errorDomain"] = "\(errorDomain)" }
        if let errorCode { metadata["errorCode"] = "\(errorCode)" }
        return metadata
    }

    /// Writes the report to the app log. A memory-cache hit or a cancelled load is debug-only: each
    /// redraw of a visible row makes one, and they would crowd out the loads worth reading.
    func log() {
        switch outcome {
        case .ok where cache == .memory:
            logger.debug("Chat photo loaded", metadata: metadata)
        case .ok:
            logger.info("Chat photo loaded", metadata: metadata)
        case .cancelled:
            logger.debug("Chat photo load cancelled", metadata: metadata)
        case .failed:
            logger.warning("Chat photo load failed", metadata: metadata)
        }
    }

    private static func name(of cache: CacheType) -> String {
        switch cache {
        case .none: "network"
        case .memory: "memory"
        case .disk: "disk"
        }
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int((duration / .milliseconds(1)).rounded())
    }
}
