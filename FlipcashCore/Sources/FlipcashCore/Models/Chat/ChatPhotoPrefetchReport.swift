//
//  ChatPhotoPrefetchReport.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Logging

private let logger = Logger(label: "flipcash.chat-media")

/// A CDN answer that was not a success, carrying its status so an expired link (403) can be told
/// from any other failure.
public struct ChatMediaHTTPError: Error, Equatable {
    public let status: Int

    public init(status: Int) {
        self.status = status
    }
}

/// The network half of one photo load: when its bytes arrived, how many, and which CDN edge sent them.
public struct ChatMediaTransfer: Equatable, Sendable {
    /// From the request starting to the first byte of the response.
    public var firstByte: Duration?
    /// From the first byte of the response to the last.
    public var body: Duration?
    public var bytes: Int64?
    public var status: Int?
    public var reusedConnection: Bool?
    /// Where URLSession took the response from: `network`, `localCache`, `serverPush` or `unknown`.
    public var fetchType: String?
    /// CloudFront's `X-Cache`: whether the edge held the object or went to the origin.
    public var xCache: String?
    /// CloudFront's `X-Amz-Cf-Pop`: the edge location that answered.
    public var pop: String?

    public init() {}

    public init(metrics: URLSessionTaskMetrics) {
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

    public init(fetchStart: Date?, responseStart: Date?, responseEnd: Date?, response: HTTPURLResponse?) {
        firstByte = Self.duration(from: fetchStart, to: responseStart)
        body = Self.duration(from: responseStart, to: responseEnd)
        if let response { record(response) }
    }

    /// Takes the status and the CDN's headers from `response`.
    public mutating func record(_ response: HTTPURLResponse) {
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

/// What started a photo prefetch, for its log line.
public enum ChatPhotoPrefetchTrigger: String, Sendable {
    /// The photo's message arrived on the live stream.
    case stream
}

/// How one photo prefetch went, logged when it ends: one `.info` line per photo considered.
public struct ChatPhotoPrefetchReport: Equatable, Sendable {

    public enum Step: String, Sendable {
        case mint
        case fetch
        case decrypt
        case decode
        case store
    }

    public enum Skip: Equatable, Sendable {
        case policy(ChatPhotoPrefetchSkip)
        /// The photo is sealed and the chat's key isn't known yet.
        case keyPending
        /// The same copy is already downloading.
        case inFlight

        var name: String {
            switch self {
            case .policy(let skip): skip.rawValue
            case .keyPending: "keyPending"
            case .inFlight: "inFlight"
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        case downloaded
        case skipped(Skip)
        case failed(Step)
    }

    public struct Failure: Error {
        public let step: Step
        public let error: (any Error)?

        public init(step: Step, error: (any Error)?) {
            self.step = step
            self.error = error
        }
    }

    public let trigger: ChatPhotoPrefetchTrigger
    public let blobID: BlobID
    public let rendition: MediaRendition.Role
    public var outcome: Outcome
    public var sealed = false
    public var mint: Duration?
    public var transfer: ChatMediaTransfer?
    public var bytes: Int?
    public var decrypt: Duration?
    public var total: Duration?
    /// The failure's error domain and code. Never its description: a `URLError` prints the failing
    /// URL, and with it the signature in its query.
    public var errorDomain: String?
    public var errorCode: Int?

    public init(trigger: ChatPhotoPrefetchTrigger, blobID: BlobID, rendition: MediaRendition.Role, outcome: Outcome) {
        self.trigger = trigger
        self.blobID = blobID
        self.rendition = rendition
        self.outcome = outcome
    }

    public mutating func fail(_ step: Step, _ error: (any Error)?) {
        outcome = .failed(step)
        guard let error else { return }
        let bridged = error as NSError
        errorDomain = bridged.domain
        errorCode = bridged.code
    }

    public var metadata: Logger.Metadata {
        var metadata: Logger.Metadata = [
            "trigger": "\(trigger.rawValue)",
            "blobId": "\(blobID)",
            "rendition": "\(rendition.rawValue)",
            "sealed": "\(sealed)",
        ]
        switch outcome {
        case .downloaded:
            metadata["outcome"] = "downloaded"
        case .skipped(let skip):
            metadata["outcome"] = "skipped"
            metadata["reason"] = "\(skip.name)"
        case .failed(let step):
            metadata["outcome"] = "failed"
            metadata["step"] = "\(step.rawValue)"
        }
        if let mint { metadata["mintMs"] = "\(Self.milliseconds(mint))" }
        if let transfer {
            if let firstByte = transfer.firstByte { metadata["firstByteMs"] = "\(Self.milliseconds(firstByte))" }
            if let body = transfer.body { metadata["bodyMs"] = "\(Self.milliseconds(body))" }
            if let status = transfer.status { metadata["status"] = "\(status)" }
            if let xCache = transfer.xCache { metadata["xCache"] = "\(xCache)" }
            if let pop = transfer.pop { metadata["pop"] = "\(pop)" }
        }
        if let bytes { metadata["bytes"] = "\(bytes)" }
        if let decrypt { metadata["decryptMs"] = "\(Self.milliseconds(decrypt))" }
        if let total { metadata["totalMs"] = "\(Self.milliseconds(total))" }
        if let errorDomain { metadata["errorDomain"] = "\(errorDomain)" }
        if let errorCode { metadata["errorCode"] = "\(errorCode)" }
        return metadata
    }

    public func log() {
        logger.info("Chat photo prefetched", metadata: metadata)
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
