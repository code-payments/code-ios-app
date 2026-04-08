import Foundation
import Testing
import Logging
@testable import FlipcashCore

@Suite("LogMiddleware Tests")
struct LogMiddlewareTests {

    // MARK: - SensitiveKeyRedactor

    @Test("SensitiveKeyRedactor redacts keys containing sensitive words")
    func sensitiveKeyRedaction() {
        let redactor = SensitiveKeyRedactor()
        var entry = makeEntry(metadata: [
            "apiToken": "abc123",
            "ownerKey": "5xJ2k...",
            "currency": "USD",
            "userEmail": "test@example.com",
            "amount": "100",
        ])

        let kept = redactor.process(&entry)

        #expect(kept)
        #expect(entry.metadata?["apiToken"] == "[REDACTED]")
        #expect(entry.metadata?["ownerKey"] == "[REDACTED]")
        #expect(entry.metadata?["userEmail"] == "[REDACTED]")
        #expect(entry.metadata?["currency"] == "USD")
        #expect(entry.metadata?["amount"] == "100")
    }

    @Test("SensitiveKeyRedactor is case-insensitive")
    func sensitiveKeyCaseInsensitive() {
        let redactor = SensitiveKeyRedactor()
        var entry = makeEntry(metadata: [
            "AccessToken": "xyz",
            "SECRET_VALUE": "hidden",
        ])

        _ = redactor.process(&entry)

        #expect(entry.metadata?["AccessToken"] == "[REDACTED]")
        #expect(entry.metadata?["SECRET_VALUE"] == "[REDACTED]")
    }

    @Test("SensitiveKeyRedactor passes entries without metadata")
    func sensitiveKeyNoMetadata() {
        let redactor = SensitiveKeyRedactor()
        var entry = makeEntry(metadata: nil)

        let kept = redactor.process(&entry)

        #expect(kept)
        #expect(entry.metadata == nil)
    }

    // MARK: - PatternRedactor

    @Test("PatternRedactor partially redacts base58 strings longer than 32 chars")
    func patternRedactorBase58() {
        let redactor = PatternRedactor()
        let base58Key = "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d" // 44 chars, valid base58
        var entry = makeEntry(metadata: [
            "mint": .string(base58Key),
            "name": "USDC",
        ])

        _ = redactor.process(&entry)

        #expect(entry.metadata?["mint"] == "5eyk...2N9d")
        #expect(entry.metadata?["name"] == "USDC")
    }

    @Test("PatternRedactor partially redacts email addresses keeping first char and domain")
    func patternRedactorEmail() {
        let redactor = PatternRedactor()
        var entry = makeEntry(metadata: [
            "contact": "user@example.com",
            "shortLocal": "a@b.com",
            "status": "active",
        ])

        _ = redactor.process(&entry)

        #expect(entry.metadata?["contact"] == "u..@example.com")
        #expect(entry.metadata?["shortLocal"] == "a..@b.com")
        #expect(entry.metadata?["status"] == "active")
    }

    @Test("PatternRedactor partially redacts phone numbers showing only last 4 digits")
    func patternRedactorPhone() {
        let redactor = PatternRedactor()
        var entry = makeEntry(metadata: [
            "withParens": "(415) 555-4321",
            "withCountry": "+1-415-555-1234",
            "digitsOnly": "4155551234",
            "code": "USD",
        ])

        _ = redactor.process(&entry)

        #expect(entry.metadata?["withParens"] == "***-***-4321")
        #expect(entry.metadata?["withCountry"] == "***-***-1234")
        #expect(entry.metadata?["digitsOnly"] == "***-***-1234")
        #expect(entry.metadata?["code"] == "USD")
    }

    @Test("PatternRedactor keeps short alphanumeric strings")
    func patternRedactorKeepsShortStrings() {
        let redactor = PatternRedactor()
        var entry = makeEntry(metadata: [
            "code": "USD",
            "count": "42",
        ])

        _ = redactor.process(&entry)

        #expect(entry.metadata?["code"] == "USD")
        #expect(entry.metadata?["count"] == "42")
    }

    // MARK: - Helpers

    private func makeEntry(metadata: Logger.Metadata?) -> LogEntry {
        LogEntry(
            timestamp: Date(),
            level: .info,
            message: "test",
            metadata: metadata,
            label: "test",
            source: "test",
            function: "test()",
            file: "Test.swift",
            line: 1
        )
    }
}
