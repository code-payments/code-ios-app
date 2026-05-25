//
//  HMACTests.swift
//  FlipcashCore
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("HMAC")
struct HMACTests {

    private func hexString(_ bytes: [Byte]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    @Test("RFC 4231 §4.2 — HMAC-SHA256", arguments: [
        (
            Data(repeating: 0x0b, count: 20),
            Data("Hi There".utf8),
            "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
        ),
    ] as [(Data, Data, String)])
    func sha256Vectors(key: Data, message: Data, expectedHex: String) {
        var hmac = HMAC(algorithm: .sha256, key: key)
        hmac.update(message)
        #expect(hexString(hmac.digestBytes()) == expectedHex)
    }

    @Test("RFC 4231 §4.3–4.4 — HMAC-SHA512", arguments: [
        (
            Data(repeating: 0x0b, count: 20),
            Data("Hi There".utf8),
            "87aa7cdea5ef619d4ff0b4241a1d6cb0" +
            "2379f4e2ce4ec2787ad0b30545e17cde" +
            "daa833b7d6b8a702038b274eaea3f4e4" +
            "be9d914eeb61f1702e696c203a126854"
        ),
        (
            Data("Jefe".utf8),
            Data("what do ya want for nothing?".utf8),
            "164b7a7bfcf819e2e395fbe73b56e0a3" +
            "87bd64222e831fd610270cd7ea250554" +
            "9758bf75c05a994a6d034f65f8f0e6fd" +
            "caeab1a34d4a6b4b636e070a38bce737"
        ),
    ] as [(Data, Data, String)])
    func sha512Vectors(key: Data, message: Data, expectedHex: String) {
        var hmac = HMAC(algorithm: .sha512, key: key)
        hmac.update(message)
        #expect(hexString(hmac.digestBytes()) == expectedHex)
    }

    @Test("Streaming update produces the same digest as a single update")
    func streamingMatchesSingle() {
        let key = Data("secret".utf8)
        let chunkA = Data("hello ".utf8)
        let chunkB = Data("world".utf8)
        let combined = chunkA + chunkB

        var streamed = HMAC(algorithm: .sha256, key: key)
        streamed.update(chunkA)
        streamed.update(chunkB)
        let streamedDigest = streamed.digestBytes()

        var single = HMAC(algorithm: .sha256, key: key)
        single.update(combined)
        let singleDigest = single.digestBytes()

        #expect(streamedDigest == singleDigest)
    }

    @Test("digestBytes() is repeatable without consuming the context")
    func digestBytesIsRepeatable() {
        var hmac = HMAC(algorithm: .sha256, key: Data("k".utf8))
        hmac.update(Data("m".utf8))
        let first = hmac.digestBytes()
        let second = hmac.digestBytes()
        #expect(first == second)
    }

    @Test("String update overload matches Data update overload")
    func stringOverloadMatchesData() {
        var a = HMAC(algorithm: .sha512, key: Data("k".utf8))
        a.update("payload")
        var b = HMAC(algorithm: .sha512, key: Data("k".utf8))
        b.update(Data("payload".utf8))
        #expect(a.digestBytes() == b.digestBytes())
    }

    @Test("digestData() and digestBytes() return equivalent bytes")
    func digestDataMatchesBytes() {
        var hmac = HMAC(algorithm: .sha256, key: Data("k".utf8))
        hmac.update("m")
        #expect(Array(hmac.digestData()) == hmac.digestBytes())
    }
}
