//
//  HTTP1ResponseReader.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The bytes of a response were not valid HTTP/1.x.
public nonisolated struct MalformedResponse: Error, Equatable, Sendable {
    public init() {}
}

/// One HTTP response with its body decoded from any chunked framing.
public nonisolated struct PinnedResponse: Sendable {
    public let status: Int
    /// Lowercased names; for a repeated header, the first value.
    public let headers: [String: String]
    public let body: Data
    /// The body was longer than the cap; `body` holds exactly the cap.
    public let truncated: Bool

    public init(status: Int, headers: [String: String], body: Data, truncated: Bool) {
        self.status = status
        self.headers = headers
        self.body = body
        self.truncated = truncated
    }

    /// Whether `Content-Type` is `text/html` or `application/xhtml+xml`.
    public var isHTML: Bool {
        guard let type = headers["content-type"]?
            .split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return type == "text/html" || type == "application/xhtml+xml"
    }
}

/// Parses an HTTP/1.x response from byte chunks as they arrive. It does no I/O.
public nonisolated struct HTTP1ResponseReader {

    public enum Progress {
        case needMore
        case done(PinnedResponse)
    }

    static let maxHeaderBytes = 32 * 1024

    private enum Phase {
        case head
        case fixed(remaining: Int)
        case chunkSize
        case chunkData(remaining: Int)
        case chunkDataEnd
        case trailers
        case untilEnd
        case finished(PinnedResponse)
    }

    private let maxBytes: Int
    private let stopsAtHeadEnd: Bool
    private var headEndScanned = 0
    private var phase = Phase.head
    private var buffer = Data()
    private var scanned = 0
    private var status = 0
    private var headers: [String: String] = [:]
    private var body = Data()

    /// With `stopsAtHeadEnd`, the body ends at the first `</head` or `<body` (P23b), the same
    /// point where the page parser stops reading.
    public init(maxBytes: Int, stopsAtHeadEnd: Bool = false) {
        self.maxBytes = maxBytes
        self.stopsAtHeadEnd = stopsAtHeadEnd
    }

    public mutating func feed(_ chunk: Data) throws -> Progress {
        if case .finished(let response) = phase { return .done(response) }
        buffer.append(chunk)
        return try advance()
    }

    /// Call at end of stream. Succeeds for a body that runs to the end of the stream; throws if
    /// the headers or a framed body were cut short.
    public mutating func finish() throws -> PinnedResponse {
        switch phase {
        case .finished(let response): return response
        case .untilEnd: return complete(truncated: false)
        default: throw MalformedResponse()
        }
    }

    // MARK: - State machine -

    private mutating func advance() throws -> Progress {
        while true {
            switch phase {
            case .finished(let response):
                return .done(response)

            case .head:
                guard try parseHead() else { return .needMore }

            case .fixed(let remaining):
                if remaining == 0 { return .done(complete(truncated: false)) }
                if body.count >= maxBytes { return .done(complete(truncated: true)) }
                guard !buffer.isEmpty else { return .needMore }
                let take = min(remaining, buffer.count, maxBytes - body.count)
                body.append(buffer.prefix(take))
                buffer = Data(buffer.dropFirst(take))
                phase = .fixed(remaining: remaining - take)
                if headEnded() { return .done(complete(truncated: false)) }

            case .chunkSize:
                guard let line = try takeLine() else { return .needMore }
                let digits = line.split(separator: ";", maxSplits: 1).first
                    .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                guard !digits.isEmpty, digits.allSatisfy(\.isHexDigit),
                      let size = Int(digits, radix: 16) else { throw MalformedResponse() }
                phase = size == 0 ? .trailers : .chunkData(remaining: size)

            case .chunkData(let remaining):
                if body.count >= maxBytes { return .done(complete(truncated: true)) }
                guard !buffer.isEmpty else { return .needMore }
                let take = min(remaining, buffer.count, maxBytes - body.count)
                body.append(buffer.prefix(take))
                buffer = Data(buffer.dropFirst(take))
                phase = remaining - take == 0 ? .chunkDataEnd : .chunkData(remaining: remaining - take)
                if headEnded() { return .done(complete(truncated: false)) }

            case .chunkDataEnd:
                guard let line = try takeLine() else { return .needMore }
                guard line.isEmpty else { throw MalformedResponse() }
                phase = .chunkSize

            case .trailers:
                guard let line = try takeLine() else { return .needMore }
                if line.isEmpty { return .done(complete(truncated: false)) }

            case .untilEnd:
                if !buffer.isEmpty {
                    let room = maxBytes - body.count
                    if buffer.count > room {
                        body.append(buffer.prefix(room))
                        buffer = Data()
                        return .done(complete(truncated: !headEnded()))
                    }
                    body.append(buffer)
                    buffer = Data()
                    if headEnded() { return .done(complete(truncated: false)) }
                }
                return .needMore
            }
        }
    }

    private static let headEndMarkers: [[UInt8]] = [Array("</head".utf8), Array("<body".utf8)]

    /// Whether the body now holds the end of the page head. Each call rescans only the bytes a
    /// marker could still finish in, so a marker split across two reads is found.
    private mutating func headEnded() -> Bool {
        guard stopsAtHeadEnd, body.count > headEndScanned else { return false }
        let longest = Self.headEndMarkers.map(\.count).max()!
        let start = max(0, headEndScanned - (longest - 1))
        headEndScanned = body.count
        let bytes = body
        let base = bytes.startIndex
        var i = base + start
        while i < bytes.endIndex {
            if bytes[i] == UInt8(ascii: "<") {
                for marker in Self.headEndMarkers where i + marker.count <= bytes.endIndex {
                    var matched = true
                    for (offset, expected) in marker.enumerated() where offset > 0 {
                        let byte = bytes[i + offset]
                        let lowered = (byte >= 65 && byte <= 90) ? byte + 32 : byte
                        if lowered != expected { matched = false; break }
                    }
                    if matched { return true }
                }
            }
            i += 1
        }
        return false
    }

    /// Reads the status line and headers once the blank line arrives, skipping interim 1xx blocks.
    private mutating func parseHead() throws -> Bool {
        let terminator = Data("\r\n\r\n".utf8)
        let from = max(0, scanned - 3)
        guard let end = buffer.range(of: terminator, in: (buffer.startIndex + from)..<buffer.endIndex) else {
            if buffer.count > Self.maxHeaderBytes { throw MalformedResponse() }
            scanned = buffer.count
            return false
        }
        guard end.lowerBound - buffer.startIndex <= Self.maxHeaderBytes else { throw MalformedResponse() }
        let block = buffer[buffer.startIndex..<end.lowerBound]
        buffer = Data(buffer[end.upperBound...])
        scanned = 0

        guard let text = String(data: block, encoding: .isoLatin1) else { throw MalformedResponse() }
        var lines = text.components(separatedBy: "\r\n")
        let statusLine = lines.removeFirst().split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard statusLine.count >= 2, statusLine[0].hasPrefix("HTTP/1."),
              statusLine[1].count == 3, let code = Int(statusLine[1]), (100...599).contains(code)
        else { throw MalformedResponse() }

        if (100..<200).contains(code) && code != 101 { return true }   // interim; the real one follows

        var parsed: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { throw MalformedResponse() }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch (parsed[name], name) {
            case (nil, _):
                parsed[name] = value
            case (let first?, "location"), (let first?, "content-length"):
                // single-valued: a repeat must agree, or the response is ambiguous
                guard first == value else { throw MalformedResponse() }
            case (let first?, _):
                parsed[name] = "\(first), \(value)"   // RFC 9110 5.3: list repeats join
            }
        }
        status = code
        headers = parsed

        if code == 204 || code == 304 || code == 101 {
            phase = .fixed(remaining: 0)
        } else if parsed["transfer-encoding"]?.lowercased().contains("chunked") == true {
            phase = .chunkSize
        } else if let length = parsed["content-length"] {
            guard let n = Int(length), n >= 0 else { throw MalformedResponse() }
            phase = .fixed(remaining: n)
        } else {
            phase = .untilEnd
        }
        return true
    }

    /// Removes and returns one CRLF-terminated line, or nil until it has fully arrived.
    private mutating func takeLine() throws -> String? {
        guard let end = buffer.range(of: Data("\r\n".utf8)) else {
            if buffer.count > Self.maxHeaderBytes { throw MalformedResponse() }
            return nil
        }
        let line = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .isoLatin1)
        buffer = Data(buffer[end.upperBound...])
        guard let line else { throw MalformedResponse() }
        return line
    }

    private mutating func complete(truncated: Bool) -> PinnedResponse {
        let response = PinnedResponse(status: status, headers: headers, body: body, truncated: truncated)
        phase = .finished(response)
        return response
    }
}
