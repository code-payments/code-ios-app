//
//  SHA512Tests.swift
//  FlipcashCore
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("SHA512")
struct SHA512Tests {

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    @Test("FIPS 180-2 short-message vectors", arguments: [
        (
            "abc",
            "ddaf35a193617abacc417349ae204131" +
            "12e6fa4e89a97ea20a9eeee64b55d39a" +
            "2192992a274fc1a836ba3c23a3feebbd" +
            "454d4423643ce80e2a9ac94fa54ca49f"
        ),
        (
            "",
            "cf83e1357eefb8bdf1542850d66d8007" +
            "d620e4050b5715dc83f4a921d36ce9ce" +
            "47d0d13c5d85f2b0ff8318d2877eec2f" +
            "63b931bd47417a81a538327af927da3e"
        ),
    ])
    func fips180_2_vectors(input: String, expectedHex: String) {
        #expect(hexString(SHA512.digest(input)) == expectedHex)
    }

    @Test("Streaming update is bit-equivalent to a single update")
    func streaming() {
        var streamed = SHA512()
        streamed.update("hello ")
        streamed.update("world")
        let streamedDigest = streamed.digestBytes()

        let oneShot = SHA512.digest("hello world")
        #expect(Array(oneShot) == streamedDigest)
    }

    @Test("Digest output is always 64 bytes regardless of input size", arguments: [
        Data(),
        Data("a".utf8),
        Data(repeating: 0xff, count: 1024),
    ])
    func digestLength(input: Data) {
        #expect(SHA512.digest(input).count == 64)
    }
}
