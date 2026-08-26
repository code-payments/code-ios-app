//
//  UsernameTests.swift
//  FlipcashCore
//

import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("Username Tests")
struct UsernameTests {

    @Test("Well-formed handles parse",
          arguments: [
              "ab",              // shortest allowed
              "ted",
              "ted_1",
              "t_9",
              "abcdefghijklmno", // longest allowed, 15 chars
          ])
    func acceptsWellFormedHandles(input: String) {
        #expect(Username(input)?.value == input)
    }

    @Test("Malformed handles are rejected",
          arguments: [
              "",                 // unclaimed, carried as an empty proto value
              "a",                // too short
              "abcdefghijklmnop", // 16 chars, too long
              "Ted",              // uppercase — the server stores lowercase only
              "ted bart",         // space
              "ted-bart",         // hyphen is outside the X character set
              "ted.bart",
              "ted@bart",
              "tedé",
              " ted",             // strict, not trimming
              "ted ",
          ])
    func rejectsMalformedHandles(input: String) {
        #expect(Username(input) == nil)
    }

    /// Persisted as a bare string so a profile row reads as `"username": "ted"`,
    /// not a nested wrapper object.
    @Test("A handle round-trips as a bare JSON string")
    func encodesAsABareString() throws {
        let username = Username("ted_1")!

        let data = try JSONEncoder().encode(username)

        #expect(String(data: data, encoding: .utf8) == "\"ted_1\"")
        #expect(try JSONDecoder().decode(Username.self, from: data) == username)
    }

    /// Decoding trusts what was written: re-validating would fail the decode of
    /// the whole enclosing profile blob over a cosmetic handle.
    @Test("Decoding does not re-validate")
    func decodingDoesNotRevalidate() throws {
        let data = Data("\"NotAValidHandle\"".utf8)

        #expect(try JSONDecoder().decode(Username.self, from: data).value == "NotAValidHandle")
    }

    @Test("The display handle prefixes @ without touching the stored value")
    func handle_prefixesAtSign() {
        let username = Username("brandon")
        #expect(username?.handle == "@brandon")
        #expect(username?.value == "brandon")
    }

    // MARK: - Proto -

    @Test("An unset proto handle maps to nil")
    func unsetProtoMapsToNil() {
        #expect(Username(Flipcash_Common_V1_Username()) == nil)
    }

    @Test("A set proto handle maps to its value")
    func setProtoMapsToItsValue() {
        let proto = Flipcash_Common_V1_Username.with { $0.value = "ted_1" }

        #expect(Username(proto)?.value == "ted_1")
    }
}
