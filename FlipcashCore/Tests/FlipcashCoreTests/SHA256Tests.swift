//
//  SHA256Tests.swift
//  FlipcashCore
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("SHA256")
struct SHA256Tests {

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    @Test("FIPS 180-2 short-message vectors", arguments: [
        (
            "abc",
            "ba7816bf8f01cfea414140de5dae2223" +
            "b00361a396177a9cb410ff61f20015ad"
        ),
        (
            "",
            "e3b0c44298fc1c149afbf4c8996fb924" +
            "27ae41e4649b934ca495991b7852b855"
        ),
    ])
    func fips180_2_vectors(input: String, expectedHex: String) {
        #expect(hexString(SHA256.digest(input)) == expectedHex)
    }

    @Test("Streaming update is bit-equivalent to a single update")
    func streaming() {
        var streamed = SHA256()
        streamed.update("hello ")
        streamed.update("world")
        let streamedDigest = streamed.digestBytes()

        let oneShot = SHA256.digest("hello world")
        #expect(Array(oneShot) == streamedDigest)
    }

    @Test("Digest output is always 32 bytes regardless of input size", arguments: [
        Data(),
        Data("a".utf8),
        Data(repeating: 0xff, count: 1024),
    ])
    func digestLength(input: Data) {
        #expect(SHA256.digest(input).count == 32)
    }
}
