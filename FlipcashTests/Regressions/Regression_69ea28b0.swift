//
//  Regression_69ea28b0.swift
//  Flipcash
//
//  Hang: StoredMintMetadata.metadata is a computed property that runs two
//        JSONDecoder.decode calls on every access (socialLinks + billColors).
//        CurrencyInfoScreen's LoadedContent.body read .metadata twice per
//        pass, so observation-churn re-evals produced a storm of decodes
//        that hung the main thread on iOS 17/18 inside SocialLink.init(from:).
//
//  Fix:  CurrencyInfoViewModel's `.loaded` enum case now carries both the
//        stored DB row and a pre-decoded MintMetadata. The decode happens
//        exactly once per state transition, and LoadedContent reads the
//        ready-made value from the enum payload.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Regression: 69ea28b0 – MintMetadata decoded once per loaded transition", .bug("69ea28b00174c05561fd0000"))
struct Regression_69ea28b0 {

    @Test("LoadingState.loaded carries both stored row and pre-decoded MintMetadata")
    func loadingStateCarriesBothPayloads() throws {
        let original = MintMetadata.makeBasic(
            socialLinks: [.x("example")],
            billColors: ["#19191A"]
        )
        let stored = StoredMintMetadata(original)

        // The regression guard: `.loaded` must expose a decoded value
        // alongside the stored row so LoadedContent never needs to call
        // `stored.metadata` (JSON decode) from its body. If a future refactor
        // drops the second associated value, this test won't compile — exactly
        // the compile-time barrier we want.
        let state: CurrencyInfoViewModel.LoadingState = .loaded(stored, stored.metadata)

        guard case .loaded(let row, let decoded) = state else {
            Issue.record("Expected .loaded case")
            return
        }
        #expect(row == stored)
        #expect(decoded.socialLinks == [.x("example")])
        #expect(decoded.billColors == ["#19191A"])
    }

    @Test("StoredMintMetadata.metadata decodes socialLinks and billColors correctly")
    func storedMetadataDecodesJSON() {
        // Covers the fallback path — if anyone else in the app still reads
        // `.metadata` directly, the decoding has to stay correct.
        let original = MintMetadata.makeBasic(
            socialLinks: [
                .website(URL(string: "https://example.com")!),
                .x("example"),
                .telegram("example"),
            ],
            billColors: ["#19191A", "#FFFFFF"]
        )
        let stored = StoredMintMetadata(original)
        let decoded = stored.metadata

        #expect(decoded.socialLinks.count == 3)
        #expect(decoded.billColors == ["#19191A", "#FFFFFF"])
    }
}
