//
//  FlipcashTests.swift
//  FlipcashTests
//
//  Created by Dima Bart on 2025-03-31.
//

import Foundation
import Testing
import FlipcashCore
import CodeScanner
@testable import Flipcash

struct CashCodeEncodingTests {

    private let nonce = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x10])

    // MARK: - Round-trip -

    @Test func roundTrip() throws {
        let payload = CashCode.Payload(kind: .cash, fiat: FiatAmount(value: 5, currency: .usd), nonce: nonce)
        let encoded = payload.encode()

        let decoded = try CashCode.Payload(data: encoded)

        #expect(payload.kind == decoded.kind)
        #expect(payload.fiat == decoded.fiat)
        #expect(payload.nonce == decoded.nonce)

        let encodedCodeData = KikCodes.encode(encoded)
        let decodedCodeData = KikCodes.decode(encodedCodeData)

        #expect(encoded == decodedCodeData)
    }

    @Test(
        "Round-trip preserves fiat across currencies and kinds",
        arguments: [
            (CashCode.Payload.Kind.cash,              CurrencyCode.usd, Decimal(string: "5.00")!),
            (CashCode.Payload.Kind.cash,              CurrencyCode.cad, Decimal(string: "7.50")!),
            (CashCode.Payload.Kind.cashMulticurrency, CurrencyCode.jpy, Decimal(1_000)),
            (CashCode.Payload.Kind.cashMulticurrency, CurrencyCode.bhd, Decimal(string: "2.345")!),
            (CashCode.Payload.Kind.cash,              CurrencyCode.usd, Decimal(string: "1.23")!),
        ]
    )
    func roundTripPreservesFiat(kind: CashCode.Payload.Kind, currency: CurrencyCode, value: Decimal) throws {
        let payload = CashCode.Payload(
            kind: kind,
            fiat: FiatAmount(value: value, currency: currency),
            nonce: nonce
        )
        let decoded = try CashCode.Payload(data: payload.encode())

        #expect(decoded.kind == kind)
        #expect(decoded.fiat.currency == currency)
        #expect(decoded.fiat.value == value)
        #expect(decoded.nonce == nonce)
    }

    // MARK: - Wire layout (guards against `wireDecimals` regressions) -

    /// The wire format is `[kind(1)][currency(1)][fiat UInt64 lower 7 bytes, little-endian][nonce(10)]`.
    /// Fiat is scaled by `wireDecimals = 6` regardless of currency — any change to that
    /// constant would produce different bytes here and fail this assertion.
    @Test func encodedBytes_matchExpectedLayout_forFiveUSD() {
        let payload = CashCode.Payload(
            kind: .cash,
            fiat: FiatAmount(value: 5, currency: .usd),
            nonce: nonce
        )
        let encoded = payload.encode()

        #expect(encoded.count == 20)
        #expect(encoded[0] == CashCode.Payload.Kind.cash.rawValue)
        #expect(encoded[1] == CurrencyCode.usd.index)

        // $5.00 × 10^6 = 5_000_000 = 0x4C_4B_40 — stored little-endian in 7 bytes.
        let fiatBytes = encoded[2..<10]
        var reconstructed: UInt64 = 0
        for (i, byte) in fiatBytes.enumerated() {
            reconstructed |= UInt64(byte) << (i * 8)
        }
        #expect(reconstructed == 5_000_000)

        #expect(Data(encoded[10..<20]) == nonce)
    }

    @Test func encodedBytes_useSixDecimalScaling() {
        // $1.23 USD with wireDecimals = 6 → 1_230_000 on the wire.
        // If `wireDecimals` ever changes (or becomes currency-aware), this test
        // pins the 6-decimal contract.
        let payload = CashCode.Payload(
            kind: .cash,
            fiat: FiatAmount(value: Decimal(string: "1.23")!, currency: .usd),
            nonce: nonce
        )
        let encoded = payload.encode()

        let fiatBytes = encoded[2..<10]
        var reconstructed: UInt64 = 0
        for (i, byte) in fiatBytes.enumerated() {
            reconstructed |= UInt64(byte) << (i * 8)
        }
        #expect(reconstructed == 1_230_000)
    }

    // MARK: - Edge cases -

    @Test func zeroFiatRoundTrip() throws {
        let payload = CashCode.Payload(
            kind: .cash,
            fiat: FiatAmount(value: 0, currency: .usd),
            nonce: nonce
        )
        let decoded = try CashCode.Payload(data: payload.encode())
        #expect(decoded.fiat.value == 0)
        #expect(decoded.fiat.currency == .usd)
    }

    @Test func singleQuarkRoundTrip() throws {
        // Smallest non-zero value representable at wireDecimals = 6 is 1 quark = $0.000001.
        let payload = CashCode.Payload(
            kind: .cash,
            fiat: FiatAmount(value: Decimal(string: "0.000001")!, currency: .usd),
            nonce: nonce
        )
        let decoded = try CashCode.Payload(data: payload.encode())
        #expect(decoded.fiat.value == Decimal(string: "0.000001")!)
    }

    @Test func differentKinds_produceDifferentRendezvous() {
        // Rendezvous is derived from the encoded bytes. Two payloads identical in
        // everything except `kind` must not share a rendezvous key.
        let fiat = FiatAmount(value: 5, currency: .usd)
        let a = CashCode.Payload(kind: .cash,              fiat: fiat, nonce: nonce)
        let b = CashCode.Payload(kind: .cashMulticurrency, fiat: fiat, nonce: nonce)
        #expect(a.rendezvous.publicKey != b.rendezvous.publicKey)
    }
}
