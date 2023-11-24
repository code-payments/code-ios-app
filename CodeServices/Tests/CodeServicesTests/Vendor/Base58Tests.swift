//
//  Base58Tests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class Base58SwiftTests: XCTestCase {
    
    /// Tuples of arbitrary strings that are mapped to valid Base58 encodings.
    private let validStringDecodedToEncodedTuples = [
        ("", ""),
        (" ", "Z"),
        ("-", "n"),
        ("0", "q"),
        ("1", "r"),
        ("-1", "4SU"),
        ("11", "4k8"),
        ("abc", "ZiCa"),
        ("1234598760", "3mJr7AoUXx2Wqd"),
        ("abcdefghijklmnopqrstuvwxyz", "3yxU3u1igY8WkgtjK92fbJQCd4BZiiT1v25f"),
        ("00000000000000000000000000000000000000000000000000000000000000", "3sN2THZeE9Eh9eYrwkvZqNstbHGvrxSAM7gXUXvyFQP8XvQLUqNCS27icwUeDT7ckHm4FUHM2mTVh1vbLmk7y"),
    ]
    
    /// Tuples of invalid strings.
    private let invalidStrings = [
        "0",
        "O",
        "I",
        "l",
        "3mJr0",
        "O3yxU",
        "3sNI",
        "4kl8",
        "0OIl",
        "!@#$%^&*()-_=+~`",
    ]
    
    func testBase58EncodingForValidStrings() {
        for (decoded, encoded) in validStringDecodedToEncodedTuples {
            let bytes = Array(decoded.utf8)
            let result = Base58.fromBytes(bytes)
            XCTAssertEqual(result, encoded)
        }
    }
    
    func testBase58DecodingForValidStrings() {
        for (decoded, encoded) in validStringDecodedToEncodedTuples {
            let bytes = Base58.toBytes(encoded)
            let result = String(bytes: bytes, encoding: .utf8)
            XCTAssertEqual(result, decoded)
        }
    }
    
    func testBase58DecodingForInvalidStrings() {
        for invalidString in invalidStrings {
            let result = Base58.toBytes(invalidString)
            XCTAssertEqual(result, [])
        }
    }
    
    func testZeroLeadingAddress() {
        let address = "13SXzojP4orzee5pjPsanK3qSzZWcrGTzgdHoVt9hQzQ"
        let bytes = Base58.toBytes(address)
        let publicKey = PublicKey(bytes)
        
        XCTAssertEqual(bytes.count, 32)
        XCTAssertNotNil(publicKey)
    }
    
    /// Taken from https://github.com/status-im/nim-stew/blob/master/tests/test_base58.nim
    private let otherTestVectors = [
        ("", ""),
        ("61", "2g"),
        ("626262", "a3gV"),
        ("636363", "aPEr"),
        ("73696d706c792061206c6f6e6720737472696e67", "2cFupjhnEsSn59qHXstmK2ffpLv2"),
        ("00eb15231dfceb60925886b67d065299925915aeb172c06647", "1NS17iag9jJgTHD1VXjvLCEnZuQ3rJDE9L"),
        ("516b6fcd0f", "ABnLTmg"),
        ("bf4f89001e670274dd", "3SEo3LWLoPntC"),
        ("572e4794", "3EFU7m"),
        ("ecac89cad93923c02321", "EJDM8drfXA6uyA"),
        ("10c8511e", "Rt5zm"),
        ("00000000000000000000", "1111111111"),
        ("000111d38e5fc9071ffcd20b4a763cc9ae4f252bb4e48fd66a835e252ada93ff480d6dd43dc62a641155a5", "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"),
        ("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", "1cWB5HCBdLjAuqGGReWE3R3CguuwSjw6RHn39s2yuDRTS5NsBgNiFpWgAnEx6VQi8csexkgYw3mdYrMHr8x9i7aEwP8kZ7vccXWqKDvGv3u1GxFKPuAkn8JCPPGDMf3vMMnbzm6Nh9zh1gcNsMvH3ZNLmP5fSG6DGbbi2tuwMWPthr4boWwCxf7ewSgNQeacyozhKDDQQ1qL5fQFUW52QKUZDZ5fw3KXNQJMcNTcaB723LchjeKun7MuGW5qyCBZYzA1KjofN1gYBV3NqyhQJ3Ns746GNuf9N2pQPmHz4xpnSrrfCvy6TVVz5d4PdrjeshsWQwpZsZGzvbdAdN8MKV5QsBDY")
    ]
    
    func testOtherTestVectors() {
        for (decoded, encoded) in otherTestVectors {
            let hexString = Base58.toBytes(encoded).data.hexEncodedString()
            XCTAssertEqual(hexString, decoded)
        }
    }
    
//    func testRandomAddresses() {
//        for _ in 0..<1_000_000 {
//            let address = PublicKey.generate()!
//            let base58 = address.base58
//            let recreated = PublicKey(base58: base58)
//            XCTAssertNotNil(recreated)
//            XCTAssertEqual(address, recreated)
//        }
//    }
}
