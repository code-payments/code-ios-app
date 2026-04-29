//
//  ReasonClassifierTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

@Suite("ReasonClassifier")
struct ReasonClassifierTests {

    private enum Classification: Equatable {
        case alpha
        case beta(String)
        case fallback
    }

    private static let classifier = ReasonClassifier<Classification>(
        rules: [
            .init(fragments: ["alpha", "first"], make: { _ in .alpha }),
            .init(fragments: ["beta"], make: { .beta($0) }),
        ],
        fallback: { _ in .fallback }
    )

    @Test("First match wins (across reasons and across rules)")
    func firstMatchWins() {
        // alpha matches first — even though beta would also match the
        // second reason.
        #expect(Self.classifier.classify(["this contains alpha", "and this beta"]) == .alpha)
    }

    @Test("Make closure receives the original (non-lowercased) reason")
    func makeReceivesOriginalReason() {
        let result = Self.classifier.classify(["Some BETA Reason"])
        #expect(result == .beta("Some BETA Reason"))
    }

    @Test("Matching is case-insensitive on both fragment and reason")
    func caseInsensitive() {
        #expect(Self.classifier.classify(["FIRST in caps"]) == .alpha)
    }

    @Test("Empty reason array goes straight to the fallback")
    func emptyArrayFallsThrough() {
        #expect(Self.classifier.classify([]) == .fallback)
    }

    @Test("Unmatched reasons fall through to the fallback")
    func unmatchedFallsThrough() {
        #expect(Self.classifier.classify(["nothing", "matches"]) == .fallback)
    }
}
