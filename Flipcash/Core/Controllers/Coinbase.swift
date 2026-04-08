//
//  Coinbase.swift
//  Code
//
//  Created by Dima Bart on 2025-08-06.
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.coinbase")

public actor Coinbase {
    
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
    
    /// Fetches the current state of an existing onramp order. Used to retrieve
    /// the on-chain `txHash` after the user has completed Apple Pay — Coinbase
    /// only populates `txHash` once `status == ONRAMP_ORDER_STATUS_COMPLETED`.
    public func fetchOrder(orderId: String) async throws -> OnrampOrderStatusResponse {
        let url = config.baseURL.appendingPathComponent("onramp/orders/\(orderId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // CDP JWTs are URI-bound — token must be minted for this exact path.
        let token = try await config.bearerTokenProvider("GET", "platform/v2/onramp/orders/\(orderId)")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await config.urlSession.data(for: urlRequest)
        } catch {
            logger.error("fetchOrder transport error", metadata: [
                "order_id": "\(orderId)",
                "error": "\(error)"
            ])
            throw Error.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if var errorResponse = try? decoder.decode(OnrampErrorResponse.self, from: data) {
                errorResponse.errorCode = http.statusCode
                logger.error("fetchOrder rejected", metadata: [
                    "order_id": "\(orderId)",
                    "error_type": "\(errorResponse.errorType)",
                    "status": "\(http.statusCode)"
                ])
                throw errorResponse
            } else {
                let body = String(data: data, encoding: .utf8) ?? "nil"
                logger.error("fetchOrder http error", metadata: [
                    "order_id": "\(orderId)",
                    "status": "\(http.statusCode)",
                    "body": "\(body)"
                ])
                throw Error.badStatus(code: http.statusCode, body: data)
            }
        }

        do {
            return try decoder.decode(OnrampOrderStatusResponse.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }

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
        
        // Bearer token (JWT per CDP docs) — scoped to POST /platform/v2/onramp/orders
        let token = try await config.bearerTokenProvider("POST", "platform/v2/onramp/orders")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // 4. Fire
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await config.urlSession.data(for: urlRequest)
        } catch {
            logger.error("createOrder transport error", metadata: ["error": "\(error)"])
            throw Error.transport(error)
        }

        // 5. Validate
        guard let http = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if var errorResponse = try? decoder.decode(OnrampErrorResponse.self, from: data) {
                errorResponse.errorCode = http.statusCode
                logger.error("createOrder rejected", metadata: [
                    "error_type": "\(errorResponse.errorType)",
                    "status": "\(http.statusCode)"
                ])
                throw errorResponse
            } else {
                let body = String(data: data, encoding: .utf8) ?? "nil"
                logger.error("createOrder http error", metadata: [
                    "status": "\(http.statusCode)",
                    "body": "\(body)"
                ])
                throw Error.badStatus(code: http.statusCode, body: data)
            }
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
    public struct Configuration: Sendable {
        public let baseURL: URL
        /// Mints a Coinbase CDP JWT scoped to a specific HTTP method + path.
        /// CDP JWTs are URI-bound, so each request needs a token signed for
        /// that exact method/path or Coinbase rejects with 401.
        public let bearerTokenProvider: @Sendable (_ method: String, _ path: String) async throws -> String
        public let urlSession: URLSession

        public init(
            baseURL: URL = URL(string: "https://api.cdp.coinbase.com/platform/v2")!,
            urlSession: URLSession = .shared,
            bearerTokenProvider: @Sendable @escaping (_ method: String, _ path: String) async throws -> String
        ) {
            self.baseURL = baseURL
            self.urlSession = urlSession
            self.bearerTokenProvider = bearerTokenProvider
        }
    }
}

// MARK: - Models -

public struct OnrampErrorResponse: Error, Decodable, Sendable {

    public var errorCode: Int?
    public var correlationId: String
    public var errorMessage: String
    public var errorType: ErrorType
    
    public var title: String {
        errorType.title
    }
    
    public var subtitle: String {
        errorType.subtitle
    }
    
    public enum ErrorType: String, Decodable, Sendable {
        case invalidCard                  = "ERROR_CODE_GUEST_INVALID_CARD"
        case transactionLimit             = "ERROR_CODE_GUEST_TRANSACTION_LIMIT"
        case transactionCount             = "ERROR_CODE_GUEST_TRANSACTION_COUNT"
        case cardRiskDeclined             = "ERROR_CODE_GUEST_CARD_RISK_DECLINED"
        case permissionDenied             = "ERROR_CODE_GUEST_PERMISSION_DENIED"
        case guestRegionMismatch          = "ERROR_CODE_GUEST_REGION_MISMATCH"
        case guestRegionForbidden         = "ERROR_CODE_GUEST_REGION_FORBIDDEN"
        
        case cardSoftDeclined             = "ERROR_CODE_GUEST_CARD_SOFT_DECLINED"
        case cardHardDeclined             = "ERROR_CODE_GUEST_CARD_HARD_DECLINED"
        case guestTransactionBuyFailed    = "ERROR_CODE_GUEST_TRANSACTION_BUY_FAILED"
        case guestTransactionSendFailed   = "ERROR_CODE_GUEST_TRANSACTION_SEND_FAILED"
        
        case guestCardInsufficientBalance = "ERROR_CODE_GUEST_CARD_INSUFFICIENT_BALANCE"
        case guestCardPrepaidDeclined     = "ERROR_CODE_GUEST_CARD_PREPAID_DECLINED"
        
        case transactionValidationFailed  = "ERROR_CODE_GUEST_TRANSACTION_AVS_VALIDATION_FAILED"
        case transactionFailed            = "ERROR_CODE_GUEST_TRANSACTION_TRANSACTION_FAILED"
        
        case networkNotTradable           = "ERROR_CODE_NETWORK_NOT_TRADABLE"
        case `internal`                   = "ERROR_CODE_INTERNAL"
        case invalidRequest               = "ERROR_CODE_INVALID_REQUEST"
        
        case applePayNotSetup             = "ERROR_CODE_GUEST_APPLE_PAY_NOT_SETUP"

        case unknown                      = "UNKNOWN"
        
        public var title: String {
                switch self {
                case .invalidCard:
                    return "Debit Cards Only"
                case .transactionLimit:
                    return "Weekly Limit Exceeded"
                case .transactionCount:
                    return "Maximum Purchases Reached"
                case .cardRiskDeclined, .permissionDenied:
                    return "Something Went Wrong"
                case .guestTransactionSendFailed, .invalidRequest:
                    return "Something Went Wrong"
                case .transactionFailed, .internal:
                    return "Something Went Wrong"
                case .guestRegionMismatch, .guestRegionForbidden, .networkNotTradable:
                    return "Your Region Isn't Supported"
                case .cardSoftDeclined, .cardHardDeclined, .guestTransactionBuyFailed:
                    return "Card Declined"
                case .guestCardInsufficientBalance:
                    return "Insufficient Funds"
                case .guestCardPrepaidDeclined:
                    return "Card Not Supported"
                case .transactionValidationFailed:
                    return "Billing Address Invalid"
                case .applePayNotSetup:
                    return "Apple Pay Not Set Up"
                case .unknown:
                    return "Something Went Wrong"
                }
            }
            
        public var subtitle: String {
                switch self {
                case .invalidCard:
                    return "This transaction was declined. Please make sure you are using a debit card and the billing address is correct"
                case .transactionLimit:
                    return "You can only add up to $1,800 per week"
                case .transactionCount:
                    return "Each user is limited to 5 purchases total. To add more funds, please purchase USDC on an exchange and deposit it into your account"
                case .cardRiskDeclined, .permissionDenied:
                    return "Something went wrong. Please contact support"
                case .guestRegionMismatch, .guestRegionForbidden, .networkNotTradable:
                    return "This feature isn't currently available in your region"
                case .cardSoftDeclined, .cardHardDeclined, .guestTransactionBuyFailed:
                    return "This transaction was declined by your bank. Please try again with a different card"
                case .guestTransactionSendFailed, .invalidRequest:
                    return "We are working with the Coinbase team to resolve the issue. Your card will be refunded in the meantime. Please try again later"
                case .guestCardInsufficientBalance:
                    return "Please make sure you have enough funds in the account linked to your debit card and try again"
                case .guestCardPrepaidDeclined:
                    return "Prepaid debit cards are not supported. Please try again with another debit card"
                case .transactionValidationFailed:
                    return "Please check that your billing address is correct and try again"
                case .transactionFailed, .internal:
                    return "The Coinbase team has been notified and is investigating the issue. Your funds will arrive once resolved. We appreciate your patience"
                case .applePayNotSetup:
                    return "It looks like you don't have a debit card linked to Apple Pay. Please link a card and try again"
                case .unknown:
                    return "Please try again later"
                }
            }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = (
                ErrorType(rawValue: rawValue.uppercased()) ??
                ErrorType(rawValue: "ERROR_CODE_\(rawValue.uppercased())")
            ) ?? .unknown
        }
    }
}

public struct OnrampOrderRequest: Encodable, Sendable {
    public var purchaseAmount: String
    public var paymentCurrency: String
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
    
    init(purchaseAmount: String, paymentCurrency: String, purchaseCurrency: String?, isQuote: Bool, destinationAddress: PublicKey, email: String, phoneNumber: String, partnerOrderRef: String, partnerUserRef: String, phoneNumberVerifiedAt: Date, agreementAcceptedAt: Date) {
        self.purchaseAmount = purchaseAmount
        self.paymentCurrency = paymentCurrency
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

public struct OnrampOrderResponse: Decodable, Identifiable, Sendable {
    public var id: String {
        order.id
    }

    public struct Order: Codable, Identifiable, Sendable {

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
    public struct PaymentLink: Codable, Sendable {
        public let url: URL
        public let paymentLinkType: String
    }
    public let order: Order
    public let paymentLink: PaymentLink
}

/// Response shape for `GET /v2/onramp/orders/{orderId}`. Unlike the create-order
/// response, this only contains the `order` envelope — no `paymentLink`.
public struct OnrampOrderStatusResponse: Decodable, Sendable {
    public let order: OnrampOrderResponse.Order
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
