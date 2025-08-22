//
//  Coinbase.swift
//  Code
//
//  Created by Dima Bart on 2025-08-06.
//

import Foundation
import FlipcashCore

public final class Coinbase {
    
    private let config: Configuration
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Init -
    
    public init(configuration: Configuration) {
        self.config = configuration
        
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - API -
    
    public func createOrder(request: OnrampOrderRequest, idempotencyKey: UUID? = nil) async throws -> OnrampOrderResponse {
        
        // 1. Build URL
        let url = config.baseURL.appendingPathComponent("onramp/orders")
        
        // 2. Encode body
        let bodyData: Data
        do {
            bodyData = try encoder.encode(request)
        } catch {
            throw Error.decoding(error)
        }
        
        // 3. Build request
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody   = bodyData
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = idempotencyKey {
            urlRequest.setValue(key.uuidString, forHTTPHeaderField: "Idempotency-Key")
        }
        
        // Bearer token (JWT per CDP docs)
        let token = try await config.bearerTokenProvider()
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // 4. Fire
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await config.urlSession.data(for: urlRequest)
        } catch {
            print("[COINBASE] \(error)")
            throw Error.transport(error)
        }
        
        // 5. Validate
        guard let http = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            print("[COINBASE] \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "nil")")
            throw Error.badStatus(code: http.statusCode, body: data)
        }
        
        // 6. Decode
        do {
            return try decoder.decode(OnrampOrderResponse.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }
}

// MARK: - Configuration -

extension Coinbase {
    public struct Configuration {
        public let baseURL: URL
        public let bearerTokenProvider: () async throws -> String
        public let urlSession: URLSession
        
        public init(
            baseURL: URL = URL(string: "https://api.cdp.coinbase.com/platform/v2")!,
            urlSession: URLSession = .shared,
            bearerTokenProvider: @escaping () async throws -> String
        ) {
            self.baseURL = baseURL
            self.urlSession = urlSession
            self.bearerTokenProvider = bearerTokenProvider
        }
    }
}

// MARK: - Models -

public struct OnrampOrderRequest: Encodable {

    public var paymentAmount: String?
    public var paymentCurrency: String
    public var purchaseAmount: String?
    public var purchaseCurrency: String?
    public var isQuote: Bool = false
    public var destinationAddress: String
    public var email: String
    public var phoneNumber: String
    public var partnerOrderRef: String
    public var partnerUserRef: String
    public var phoneNumberVerifiedAt: Date
    public var agreementAcceptedAt: Date
    
    public let destinationNetwork: String = "solana"
    public let paymentMethod: String = "GUEST_CHECKOUT_APPLE_PAY"
    
    init(paymentAmount: String?, paymentCurrency: String, purchaseAmount: String?, purchaseCurrency: String?, isQuote: Bool, destinationAddress: PublicKey, email: String, phoneNumber: String, partnerOrderRef: String, partnerUserRef: String, phoneNumberVerifiedAt: Date, agreementAcceptedAt: Date) {
        self.paymentAmount = paymentAmount
        self.paymentCurrency = paymentCurrency
        self.purchaseAmount = purchaseAmount
        self.purchaseCurrency = purchaseCurrency
        self.isQuote = isQuote
        self.destinationAddress = destinationAddress.base58
        self.email = email
        self.phoneNumber = phoneNumber
        self.partnerOrderRef = partnerOrderRef
        self.partnerUserRef = partnerUserRef
        self.phoneNumberVerifiedAt = phoneNumberVerifiedAt
        self.agreementAcceptedAt = agreementAcceptedAt
    }
}

public struct OnrampOrderResponse: Decodable, Identifiable {
    public var id: String {
        order.id
    }
    
    public struct Order: Codable, Identifiable {
        
        public var id: String { orderId }
        
        public let orderId: String
        public let status: String
        public let paymentTotal: String?
        public let paymentCurrency: String?
        public let purchaseAmount: String?
        public let purchaseCurrency: String?
        public let destinationAddress: String
        public let destinationNetwork: String
        public let txHash: String?
        public let createdAt: Date
        public let updatedAt: Date
    }
    public struct PaymentLink: Codable {
        public let url: URL
        public let paymentLinkType: String
    }
    public let order: Order
    public let paymentLink: PaymentLink
}

// MARK: - Error -

extension Coinbase {
    public enum Error: Swift.Error {
        case badStatus(code: Int, body: Data)
        case invalidResponse
        case decoding(Swift.Error)
        case transport(Swift.Error)
    }
}

/*
 
{
    "purchaseAmount": "10.00",
    "partnerUserRef": "sandbox-dima",
    "paymentMethod": "GUEST_CHECKOUT_APPLE_PAY",
    "partnerOrderRef": "dimasorder1",
    "email": "dima.bart01@gmail.com",
    "phoneNumber": "+15615557689",
    "paymentCurrency": "cad",
    "purchaseCurrency": "usdc",
    "destinationAddress": "C4BEeePWFG1dyZe1QFBwEJHRabZw9thaB8RhgE7kUvKr",
    "destinationNetwork": "solana",
    "phoneNumberVerifiedAt": "2025-08-08T19:06:05Z",
    "agreementAcceptedAt": "2025-08-08T19:06:05Z",
    "isQuote": true
}

{
    "purchaseAmount": "10",
    "partnerUserRef": "sandbox-iob9Nc3sQfejRtBhsTYSfg==",
    "paymentMethod": "GUEST_CHECKOUT_APPLE_PAY",
    "email": "brandon.mcansh@gmail.com",
    "phoneNumber": "+(1)5869802333",
    "paymentCurrency": "USD",
    "purchaseCurrency": "USDC",
    "destinationAddress": "9e8zSubWQiz3iA6Nyu5NWGdcPJtc2zc4XQaztr1Xvvqy",
    "destinationNetwork": "solana",
    "phoneNumberVerifiedAt": "2025-07-27:00:00Z",
    "agreementAcceptedAt": "2025-07-27T00:00:00Z"
}
 
*/
