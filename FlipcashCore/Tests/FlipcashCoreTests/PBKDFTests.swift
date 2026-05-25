//
//  PBKDFTests.swift
//  FlipcashCore
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("PBKDF2")
struct PBKDFTests {

    private func hexString(_ bytes: [Byte]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    @Test("PBKDF2-HMAC-SHA512: password=\"password\", salt=\"salt\", rounds=1")
    func pbkdf2_sha512_rounds1() {
        let bytes = PBKDF.deriveKey(algorithm: .sha512, password: "password", salt: "salt", rounds: 1)
        #expect(bytes.count == 64)
        #expect(hexString(bytes) ==
            "867f70cf1ade02cff3752599a3a53dc4" +
            "af34c7a669815ae5d513554e1c8cf252" +
            "c02d470a285a0501bad999bfe943c08f" +
            "050235d7d68b1da55e63f73b60a57fce"
        )
    }

    @Test("Rounds parameter affects output")
    func pbkdf2_sha512_roundsAffectsOutput() {
        let round1 = PBKDF.deriveKey(algorithm: .sha512, password: "password", salt: "salt", rounds: 1)
        let round2 = PBKDF.deriveKey(algorithm: .sha512, password: "password", salt: "salt", rounds: 2)
        #expect(round1 != round2)
    }

    @Test("PBKDF2-HMAC-SHA256 output is exactly 32 bytes")
    func pbkdf2_sha256_digestLength() {
        let bytes = PBKDF.deriveKey(algorithm: .sha256, password: "password", salt: "salt", rounds: 10)
        #expect(bytes.count == 32)
    }

    @Test("Identical inputs produce identical output")
    func pbkdf2_deterministic() {
        let a = PBKDF.deriveKey(algorithm: .sha512, password: "p", salt: "s", rounds: 8)
        let b = PBKDF.deriveKey(algorithm: .sha512, password: "p", salt: "s", rounds: 8)
        #expect(a == b)
    }

    @Test("Different salts produce different outputs")
    func pbkdf2_saltMatters() {
        let a = PBKDF.deriveKey(algorithm: .sha512, password: "p", salt: "sa", rounds: 4)
        let b = PBKDF.deriveKey(algorithm: .sha512, password: "p", salt: "sb", rounds: 4)
        #expect(a != b)
    }
}
