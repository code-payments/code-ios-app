//
//  HTTP1ResponseReaderTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore

@Suite("HTTP1ResponseReader")
struct HTTP1ResponseReaderTests {

    private static func bytes(_ text: String) -> Data { Data(text.utf8) }

    /// Feeds `data` whole, then at end of stream if it was not already done.
    private func read(_ data: Data, maxBytes: Int = 1024, stopsAtHeadEnd: Bool = false, byteAtATime: Bool) throws -> PinnedResponse {
        var reader = HTTP1ResponseReader(maxBytes: maxBytes, stopsAtHeadEnd: stopsAtHeadEnd)
        let pieces = byteAtATime ? data.map { Data([$0]) } : [data]
        for piece in pieces {
            if case .done(let response) = try reader.feed(piece) { return response }
        }
        return try reader.finish()
    }

    private static let cases: [(name: String, wire: String, body: String)] = [
        ("content-length",
         "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 5\r\n\r\nhello", "hello"),
        ("chunked with extensions and trailers",
         "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3;ext=1\r\nhel\r\n2\r\nlo\r\n0\r\nX-Trailer: a\r\n\r\n", "hello"),
        ("read to end",
         "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nhello", "hello"),
    ]

    @Test(arguments: [false, true])
    func decodesEachFraming(byteAtATime: Bool) throws {
        for c in Self.cases {
            let response = try read(Self.bytes(c.wire), byteAtATime: byteAtATime)
            #expect(response.status == 200, "\(c.name)")
            #expect(String(decoding: response.body, as: UTF8.self) == c.body, "\(c.name)")
            #expect(!response.truncated, "\(c.name)")
        }
    }

    @Test func contentLengthCompletesWithoutEndOfStream() throws {
        var reader = HTTP1ResponseReader(maxBytes: 100)
        guard case .done(let response) = try reader.feed(Self.bytes("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi")) else {
            Issue.record("not done"); return
        }
        #expect(response.body == Data("hi".utf8))
    }

    @Test(arguments: [false, true])
    func oversizedHeaderBlockIsMalformed(byteAtATime: Bool) {
        let wire = Self.bytes("HTTP/1.1 200 OK\r\nX-Big: " + String(repeating: "a", count: 33 * 1024) + "\r\n\r\n")
        #expect(throws: MalformedResponse.self) { try read(wire, byteAtATime: byteAtATime) }
    }

    @Test func badStatusLineIsMalformed() {
        #expect(throws: MalformedResponse.self) { try read(Self.bytes("NOPE\r\n\r\n"), byteAtATime: false) }
        #expect(throws: MalformedResponse.self) { try read(Self.bytes("HTTP/1.1 abc OK\r\n\r\n"), byteAtATime: false) }
    }

    @Test func endOfStreamBeforeHeadersIsMalformed() {
        #expect(throws: MalformedResponse.self) { try read(Self.bytes("HTTP/1.1 200 OK\r\n"), byteAtATime: false) }
    }

    @Test(arguments: [false, true])
    func bodyPastTheCapKeepsExactlyTheCap(byteAtATime: Bool) throws {
        let framings = [
            "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\n0123456789",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n6\r\n012345\r\n4\r\n6789\r\n0\r\n\r\n",
            "HTTP/1.1 200 OK\r\n\r\n0123456789",
        ]
        for wire in framings {
            let response = try read(Self.bytes(wire), maxBytes: 4, byteAtATime: byteAtATime)
            #expect(response.truncated)
            #expect(response.body == Data("0123".utf8))
        }
    }

    @Test func bodyExactlyTheCapIsNotTruncated() throws {
        let response = try read(Self.bytes("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\n0123"), maxBytes: 4, byteAtATime: false)
        #expect(!response.truncated)
        #expect(response.body.count == 4)
    }

    @Test(arguments: [false, true])
    func skipsInterimContinue(byteAtATime: Bool) throws {
        let wire = Self.bytes("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
        let response = try read(wire, byteAtATime: byteAtATime)
        #expect(response.status == 200)
        #expect(response.body == Data("ok".utf8))
    }

    @Test func headerNamesAreCaseInsensitive() throws {
        let wire = "HTTP/1.1 301 Moved\r\nLOCATION: https://a.example/\r\nlocation: https://a.example/\r\nContent-Length: 0\r\n\r\n"
        let response = try read(Self.bytes(wire), byteAtATime: false)
        #expect(response.headers["location"] == "https://a.example/")
    }

    /// D17: a list header that repeats joins, so every Content-Encoding value is seen.
    @Test func repeatedListHeadersJoin() throws {
        let wire = "HTTP/1.1 200 OK\r\nContent-Encoding: identity\r\nContent-Encoding: gzip\r\nContent-Length: 0\r\n\r\n"
        #expect(try read(Self.bytes(wire), byteAtATime: false).headers["content-encoding"] == "identity, gzip")
    }

    @Test(arguments: ["Location: https://a.example/\r\nLocation: https://b.example/", "Content-Length: 1\r\nContent-Length: 2"])
    func conflictingSingleValuedHeadersAreMalformed(_ headers: String) {
        let wire = Self.bytes("HTTP/1.1 301 Moved\r\n\(headers)\r\n\r\n")
        #expect(throws: MalformedResponse.self) { try read(wire, byteAtATime: false) }
    }

    @Test func isHTMLReadsTheMediaType() throws {
        func html(_ type: String) throws -> Bool {
            try read(Self.bytes("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: 0\r\n\r\n"), byteAtATime: false).isHTML
        }
        #expect(try html("text/html; charset=utf-8"))
        #expect(try html("Application/XHTML+xml"))
        #expect(try !html("application/json"))
    }

    @Test(arguments: ["</HEAD>", "<BoDy>"])
    func stopsAtTheHeadEndInEachFraming(_ marker: String) throws {
        let page = "<html><head><title>a</title>\(marker)" + String(repeating: "x", count: 64)
        let framings = [
            "HTTP/1.1 200 OK\r\nContent-Length: \(page.utf8.count)\r\n\r\n\(page)",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n\(String(page.utf8.count, radix: 16))\r\n\(page)\r\n0\r\n\r\n",
            "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n\(page)",
        ]
        for wire in framings {
            // Byte at a time splits the marker across reads, and nothing past it is read.
            var reader = HTTP1ResponseReader(maxBytes: 1024, stopsAtHeadEnd: true)
            var stopped: PinnedResponse?
            for byte in Self.bytes(wire) {
                if case .done(let response) = try reader.feed(Data([byte])) { stopped = response; break }
            }
            let response = try #require(stopped, "\(wire)")
            let body = String(decoding: response.body, as: UTF8.self)
            #expect(body.hasSuffix(String(marker.dropLast())), "\(wire)")
            #expect(!response.truncated)
        }
    }

    @Test func readsTheWholeBodyWithoutTheHeadStop() throws {
        let page = "<head></head><body>tail"
        let response = try read(Self.bytes("HTTP/1.1 200 OK\r\nContent-Length: \(page.utf8.count)\r\n\r\n\(page)"), byteAtATime: true)
        #expect(String(decoding: response.body, as: UTF8.self) == page)
    }

    @Test func aPageWithNoHeadEndReadsToTheCap() throws {
        let response = try read(Self.bytes("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n" + String(repeating: "x", count: 40)),
                                maxBytes: 16, stopsAtHeadEnd: true, byteAtATime: false)
        #expect(response.body.count == 16)
        #expect(response.truncated)
    }
}
