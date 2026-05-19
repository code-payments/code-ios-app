//
//  OnrampOrderResponse+Fixtures.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash

extension OnrampOrderResponse {

    /// Builds a fixture by Decoding from JSON — `OnrampOrderResponse` and its
    /// nested `Order`/`PaymentLink` types only have synthesized inits, which
    /// are not accessible across module boundaries even with `@testable`.
    static func fixture(
        orderId: String = "order-\(UUID().uuidString)",
        purchaseAmount: String? = "10.00",
        paymentLinkURL: URL = URL(string: "https://pay.coinbase.com/test")!
    ) -> OnrampOrderResponse {
        let json: [String: Any] = [
            "order": [
                "orderId": orderId,
                "status": "pending",
                "paymentTotal": "10.00",
                "paymentCurrency": "USD",
                "purchaseAmount": purchaseAmount as Any,
                "purchaseCurrency": "USDF",
                "destinationAddress": "destination",
                "destinationNetwork": "solana",
                "txHash": NSNull(),
                "createdAt": ISO8601DateFormatter().string(from: .init(timeIntervalSince1970: 0)),
                "updatedAt": ISO8601DateFormatter().string(from: .init(timeIntervalSince1970: 0))
            ],
            "paymentLink": [
                "url": paymentLinkURL.absoluteString,
                "paymentLinkType": "applepay"
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(OnrampOrderResponse.self, from: data)
    }
}
