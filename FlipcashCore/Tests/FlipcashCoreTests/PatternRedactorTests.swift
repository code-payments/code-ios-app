//
//  PatternRedactorTests.swift
//  FlipcashCore
//

import Foundation
import Testing
import Logging
@testable import FlipcashCore

@Suite("PatternRedactor")
struct PatternRedactorTests {

    private func process(_ metadata: Logger.Metadata) -> Logger.Metadata {
        var entry = LogEntry(
            timestamp: Date(),
            level: .info,
            message: "msg",
            metadata: metadata,
            label: "test",
            source: "test",
            function: "y",
            file: "x",
            line: 1
        )
        _ = PatternRedactor().process(&entry)
        return entry.metadata ?? [:]
    }

    // MARK: - Phone redaction

    @Test("E.164 phone with + prefix is redacted")
    func phone_e164IsRedacted() {
        let out = process(["contact": "+17205551234"])
        #expect(out["contact"] == "***-***-1234")
    }

    @Test("Human-formatted phone with dashes is redacted")
    func phone_dashedIsRedacted() {
        let out = process(["contact": "720-555-1234"])
        #expect(out["contact"] == "***-***-1234")
    }

    @Test("Human-formatted phone with parens is redacted")
    func phone_parenIsRedacted() {
        let out = process(["contact": "(720) 555-1234"])
        #expect(out["contact"] == "***-***-1234")
    }

    // MARK: - Integer values must NOT be mistaken for phones

    @Test(
        "Plain integer amounts (quarks) pass through untouched",
        arguments: [
            "1234567",      // 7 digits — the shortest phone-length collision
            "7309069",      // 7 digits
            "10000000",     // 8 digits
            "100000000",    // 9 digits
            "1234567890",   // 10 digits — NANP length collision
            "7309069770",   // 10 digits
            "10000000000",  // 11 digits
        ]
    )
    func integerAmount_isNotRedacted(digits: String) {
        let out = process(["amountQuarks": .string(digits)])
        #expect(out["amountQuarks"] == .string(digits))
    }

    // MARK: - Base58 key redaction (left intact by this change)

    @Test("Long base58 string is redacted to first4...last4")
    func base58_isRedacted() {
        let key = "5AMAtkPEvQcESp3h1yBL7k7RcVxEp3SqL8m2TfTCYAUQ"
        let out = process(["publicKey": .string(key)])
        #expect(out["publicKey"] == .string("5AMA...YAUQ"))
    }
}
