//
//  OnrampOrderRequestTests.swift
//  Flipcash
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("OnrampOrderRequest JSON encoding")
struct OnrampOrderRequestTests {

    private static let destination = try! PublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")

    private func makeRequest(
        purchaseAmount: String = "10.00",
        paymentCurrency: String = "USD",
        purchaseCurrency: String? = "USDF",
        isQuote: Bool = false,
    ) -> OnrampOrderRequest {
        OnrampOrderRequest(
            purchaseAmount: purchaseAmount,
            paymentCurrency: paymentCurrency,
            purchaseCurrency: purchaseCurrency,
            isQuote: isQuote,
            destinationAddress: Self.destination,
            email: "buyer@example.com",
            phoneNumber: "+15555550123",
            partnerOrderRef: "order-ref-1",
            partnerUserRef: "user-ref-1",
            phoneNumberVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            agreementAcceptedAt: Date(timeIntervalSince1970: 1_700_000_100),
        )
    }

    private func encode(_ request: OnrampOrderRequest) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test("destinationNetwork is hardcoded to \"solana\"")
    func destinationNetworkHardcoded() throws {
        let json = try encode(makeRequest())
        #expect(json["destinationNetwork"] as? String == "solana")
    }

    @Test("paymentMethod is hardcoded to GUEST_CHECKOUT_APPLE_PAY")
    func paymentMethodHardcoded() throws {
        let json = try encode(makeRequest())
        #expect(json["paymentMethod"] as? String == "GUEST_CHECKOUT_APPLE_PAY")
    }

    @Test("destinationAddress is encoded as the base58 form of the PublicKey")
    func destinationAddressIsBase58() throws {
        let json = try encode(makeRequest())
        #expect(json["destinationAddress"] as? String == Self.destination.base58)
    }

    @Test("All required wire-contract fields are present")
    func allRequiredKeysPresent() throws {
        let json = try encode(makeRequest())
        let required: [String] = [
            "purchaseAmount",
            "paymentCurrency",
            "purchaseCurrency",
            "isQuote",
            "destinationAddress",
            "destinationNetwork",
            "email",
            "phoneNumber",
            "partnerOrderRef",
            "partnerUserRef",
            "phoneNumberVerifiedAt",
            "agreementAcceptedAt",
            "paymentMethod",
        ]
        for key in required {
            #expect(json.keys.contains(key), "Missing key: \(key)")
        }
    }

    @Test("Both timestamp fields encode as ISO 8601 strings with T separator and Z UTC suffix")
    func timestampsAreIso8601Strings() throws {
        let json = try encode(makeRequest())
        let verifiedAt = try #require(json["phoneNumberVerifiedAt"] as? String)
        let acceptedAt = try #require(json["agreementAcceptedAt"] as? String)
        #expect(verifiedAt.contains("T"))
        #expect(verifiedAt.hasSuffix("Z"))
        #expect(acceptedAt.contains("T"))
        #expect(acceptedAt.hasSuffix("Z"))
    }

    @Test("purchaseCurrency is omitted from the JSON when nil")
    func purchaseCurrencyNilOmitted() throws {
        let json = try encode(makeRequest(purchaseCurrency: nil))
        #expect(json["purchaseCurrency"] == nil)
    }

    @Test("Caller-supplied amounts and refs round-trip verbatim")
    func userInputsPassThrough() throws {
        let request = makeRequest(purchaseAmount: "42.75", paymentCurrency: "USD")
        let json = try encode(request)
        #expect(json["purchaseAmount"] as? String == "42.75")
        #expect(json["paymentCurrency"] as? String == "USD")
        #expect(json["email"] as? String == "buyer@example.com")
        #expect(json["phoneNumber"] as? String == "+15555550123")
        #expect(json["partnerOrderRef"] as? String == "order-ref-1")
        #expect(json["partnerUserRef"] as? String == "user-ref-1")
    }

    @Test("isQuote defaults to false")
    func isQuoteDefaultsFalse() throws {
        let json = try encode(makeRequest())
        #expect(json["isQuote"] as? Bool == false)
    }

    @Test("isQuote = true is encoded as true")
    func isQuoteTrueRoundtrip() throws {
        let json = try encode(makeRequest(isQuote: true))
        #expect(json["isQuote"] as? Bool == true)
    }
}
