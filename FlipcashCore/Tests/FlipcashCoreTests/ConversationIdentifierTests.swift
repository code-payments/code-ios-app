//
//  ConversationIdentifierTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("ConversationID base64url decoding")
struct ConversationIdentifierTests {

    @Test("Decodes the server's padded base64url form")
    func decodesPadded() throws {
        let data = Data((0..<32).map { UInt8($0) })
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        let id = try #require(ConversationID(base64URLEncoded: encoded))
        #expect(id.data == data)
    }

    @Test("Decodes unpadded input")
    func decodesUnpadded() throws {
        let data = Data((0..<32).map { UInt8($0) })
        let unpadded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let id = try #require(ConversationID(base64URLEncoded: unpadded))
        #expect(id.data == data)
    }

    @Test("Maps the URL-safe alphabet back to standard base64")
    func decodesURLSafeAlphabet() throws {
        let data = Data(repeating: 0xFB, count: 32)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        #expect(encoded.contains("-") && encoded.contains("_"))

        let id = try #require(ConversationID(base64URLEncoded: encoded))
        #expect(id.data == data)
    }

    @Test("Rejects values that are not exactly 32 bytes", arguments: [0, 16, 31, 33])
    func rejectsWrongLength(count: Int) {
        let encoded = Data(repeating: 0x01, count: count).base64EncodedString()
        #expect(ConversationID(base64URLEncoded: encoded) == nil)
    }

    @Test("Rejects input that is not base64")
    func rejectsGarbage() {
        #expect(ConversationID(base64URLEncoded: "not.valid.base64") == nil)
    }
}
