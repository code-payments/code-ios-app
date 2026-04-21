//
//  VerifiedStateResolutionTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@Suite("VerifiedStateResolution")
struct VerifiedStateResolutionTests {

    private let currency: CurrencyCode = .usd
    private let mint: PublicKey = .jeffy

    private func makeState(rate: Double = 1.0) -> VerifiedState {
        VerifiedState(
            rateProto: .makeTest(currencyCode: currency.rawValue, rate: rate)
        )
    }

    @Test("Provided state is returned without consulting the cache")
    func provided_short_circuitsCache() async {
        let provided = makeState(rate: 1.23)
        var cacheCalls = 0

        let result = await resolveVerifiedState(
            provided: provided,
            currency: currency,
            mint: mint,
            cacheLookup: { _, _ in
                cacheCalls += 1
                return self.makeState(rate: 9.99)
            }
        )

        #expect(result == .provided(provided))
        #expect(cacheCalls == 0)
    }

    @Test("Cache-hit returned when nothing is provided")
    func cacheHit_returnedWhenProvidedNil() async {
        let cached = makeState(rate: 7.5)

        let result = await resolveVerifiedState(
            provided: nil,
            currency: currency,
            mint: mint,
            cacheLookup: { _, _ in cached }
        )

        #expect(result == .cacheHit(cached))
    }

    @Test("Cache-miss when provided is nil and cache yields nil")
    func cacheMiss_whenBothSourcesEmpty() async {
        let result = await resolveVerifiedState(
            provided: nil,
            currency: currency,
            mint: mint,
            cacheLookup: { _, _ in nil }
        )

        #expect(result == .cacheMiss)
        #expect(result.state == nil)
    }

    @Test("Cache lookup receives the requested currency and mint")
    func cacheLookup_receivesCorrectArguments() async {
        var receivedCurrency: CurrencyCode?
        var receivedMint: PublicKey?

        _ = await resolveVerifiedState(
            provided: nil,
            currency: currency,
            mint: mint,
            cacheLookup: { c, m in
                receivedCurrency = c
                receivedMint = m
                return nil
            }
        )

        #expect(receivedCurrency == currency)
        #expect(receivedMint == mint)
    }

    @Test("sourceLabel produces stable log strings")
    func sourceLabel_stableStrings() {
        let state = makeState()
        #expect(VerifiedStateResolution.provided(state).sourceLabel == "provided")
        #expect(VerifiedStateResolution.cacheHit(state).sourceLabel == "cache-hit")
        #expect(VerifiedStateResolution.cacheMiss.sourceLabel == "cache-miss")
    }
}
