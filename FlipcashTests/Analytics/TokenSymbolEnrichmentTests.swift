//
//  TokenSymbolEnrichmentTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Token symbol enrichment")
struct TokenSymbolEnrichmentTests {

    @Test("Property names are the shared contract")
    func propertyNames() {
        #expect(Analytics.Property.tokenSymbol.rawValue == "Token Symbol")
        #expect(Analytics.Property.paymentTokenSymbol.rawValue == "Payment Token Symbol")
    }

    @Test("A resolvable Mint gains Token Symbol")
    func mintGainsSymbol() {
        let properties: [Analytics.Property: AnalyticsValue] = [.mint: "SomeMint"]
        let enriched = Analytics.withTokenSymbols(properties) { _ in "FLIP" }
        #expect(enriched[.tokenSymbol] as? String == "FLIP")
    }

    @Test("A resolvable Payment Mint gains Payment Token Symbol")
    func paymentMintGainsSymbol() {
        let properties: [Analytics.Property: AnalyticsValue] = [.paymentMint: "SomeMint"]
        let enriched = Analytics.withTokenSymbols(properties) { _ in "USDF" }
        #expect(enriched[.paymentTokenSymbol] as? String == "USDF")
    }

    @Test("Both mints resolve independently")
    func bothMintsResolve() {
        let properties: [Analytics.Property: AnalyticsValue] = [
            .mint: "target",
            .paymentMint: "payment",
        ]
        let enriched = Analytics.withTokenSymbols(properties) { base58 in
            base58 == "target" ? "FLIP" : "USDF"
        }
        #expect(enriched[.tokenSymbol] as? String == "FLIP")
        #expect(enriched[.paymentTokenSymbol] as? String == "USDF")
    }

    @Test("An unresolvable mint omits the symbol entirely")
    func unresolvedMintOmitsSymbol() {
        let properties: [Analytics.Property: AnalyticsValue] = [.mint: "SomeMint"]
        let enriched = Analytics.withTokenSymbols(properties) { _ in nil }
        #expect(enriched[.tokenSymbol] == nil)
        #expect(enriched.count == properties.count)
    }

    @Test("Properties without a mint pass through untouched")
    func noMintPassesThrough() {
        let properties: [Analytics.Property: AnalyticsValue] = [.state: "Success"]
        let enriched = Analytics.withTokenSymbols(properties) { _ in "FLIP" }
        #expect(enriched[.tokenSymbol] == nil)
        #expect(enriched[.paymentTokenSymbol] == nil)
        #expect(enriched.count == 1)
    }
}
