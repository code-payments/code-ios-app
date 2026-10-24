//
//  PaymentRequestService.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.payment-request-service")

final class PaymentRequestService: Sendable {

    private let service: Flipcash_Paymentrequest_V1_PaymentRequest.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Paymentrequest_V1_PaymentRequest.Client(wrapping: client)
    }

    struct Fetched: Sendable {
        let request: GroupPaymentRequest
        /// The intent id the caller's share payment must use; set only for a caller holding an unpaid share.
        let paymentIntentID: Data?
    }

    struct ChatPage: Sendable {
        let requests: [GroupPaymentRequest]
        let pagingToken: Data
        let hasMore: Bool
    }

    /// Creates a split in a group chat. `idempotencyKey` is reused across retries; a retry returns
    /// the original request. `.textModerated` carries the category the server flagged.
    func createPaymentRequest(owner: KeyPair, idempotencyKey: Data, chatID: ConversationID, split: GroupPaymentRequest.Split, completion: @Sendable @escaping (Result<GroupPaymentRequest, ErrorCreatePaymentRequest>) -> Void) {
        let request = Flipcash_Paymentrequest_V1_CreatePaymentRequestRequest.with {
            $0.idempotencyKey = .with { $0.value = idempotencyKey }
            $0.groupChat = .with {
                $0.chatID = chatID.proto
                $0.split = split.proto
            }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.createPaymentRequest(request, options: .unaryDefault)
                guard response.result == .ok else {
                    logger.error("Failed to create payment request", metadata: ["result": "\(response.result.rawValue)"])
                    await MainActor.run { completion(.failure(ErrorCreatePaymentRequest(response.result, flaggedCategory: response.flaggedCategory))) }
                    return
                }
                guard let created = GroupPaymentRequest(response.paymentRequest) else {
                    logger.error("Created payment request was malformed")
                    await MainActor.run { completion(.failure(.unknown)) }
                    return
                }
                await MainActor.run { completion(.success(created)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func getPaymentRequest(owner: KeyPair, id: PaymentRequestID, completion: @Sendable @escaping (Result<Fetched, ErrorGetPaymentRequest>) -> Void) {
        let request = Flipcash_Paymentrequest_V1_GetPaymentRequestRequest.with {
            $0.paymentRequestID = id.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getPaymentRequest(request, options: .unaryDefault)
                let error = ErrorGetPaymentRequest(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch payment request", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                guard let fetched = GroupPaymentRequest(response.paymentRequest) else {
                    logger.error("Fetched payment request was malformed")
                    await MainActor.run { completion(.failure(.unknown)) }
                    return
                }
                let result = Fetched(
                    request: fetched,
                    paymentIntentID: response.hasPaymentIntentID ? response.paymentIntentID.value : nil
                )
                await MainActor.run { completion(.success(result)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func getChatPaymentRequests(owner: KeyPair, conversationID: ConversationID, section: GroupPaymentRequest.Section, pageSize: Int = 50, pagingToken: Data?, completion: @Sendable @escaping (Result<ChatPage, ErrorGetChatPaymentRequests>) -> Void) {
        let request = Flipcash_Paymentrequest_V1_GetChatPaymentRequestsRequest.with {
            $0.chatID = conversationID.proto
            $0.section = section.proto
            $0.queryOptions = .with {
                $0.pageSize = Int32(pageSize)
                if let pagingToken {
                    $0.pagingToken = .with { $0.value = pagingToken }
                }
            }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getChatPaymentRequests(request, options: .unaryDefault)
                let error = ErrorGetChatPaymentRequests(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch chat payment requests", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                let page = ChatPage(
                    requests: response.paymentRequests.compactMap(GroupPaymentRequest.init),
                    pagingToken: response.pagingToken.value,
                    hasMore: response.hasMore_p
                )
                await MainActor.run { completion(.success(page)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Closes an open request. Creator only.
    func closePaymentRequest(owner: KeyPair, id: PaymentRequestID, completion: @Sendable @escaping (Result<GroupPaymentRequest, ErrorClosePaymentRequest>) -> Void) {
        let request = Flipcash_Paymentrequest_V1_ClosePaymentRequestRequest.with {
            $0.paymentRequestID = id.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.closePaymentRequest(request, options: .unaryDefault)
                let error = ErrorClosePaymentRequest(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, let closed = GroupPaymentRequest(response.paymentRequest) else {
                    logger.error("Failed to close payment request", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(closed)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Marks `userID`'s share paid out of band. Creator only.
    func markPaid(owner: KeyPair, id: PaymentRequestID, userID: UserID, completion: @Sendable @escaping (Result<GroupPaymentRequest, ErrorMarkPaid>) -> Void) {
        let request = Flipcash_Paymentrequest_V1_MarkPaidRequest.with {
            $0.paymentRequestID = id.proto
            $0.userID = userID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.markPaid(request, options: .unaryDefault)
                let error = ErrorMarkPaid(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, let updated = GroupPaymentRequest(response.paymentRequest) else {
                    logger.error("Failed to mark payment request share paid", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(updated)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

/// Associated-value error, modelled on ``ErrorEditChat``, so `.textModerated` can carry the
/// `flaggedCategory` the server reports. Mapped explicitly from `CreatePaymentRequestResponse.Result`;
/// there is no `.ok` case.
public enum ErrorCreatePaymentRequest: Error, Sendable, Equatable {
    case denied
    case chatNotSupported
    case encryptionNotAllowed
    case encryptionRequired
    case invalidEndsAt
    case invalidShares
    case invalidCurrency
    case textModerated(Flipcash_Moderation_V1_FlaggedCategory)
    case unknown
    case transportFailure
    case cancelled
    case rejected
}

extension ErrorCreatePaymentRequest {
    init(_ result: Flipcash_Paymentrequest_V1_CreatePaymentRequestResponse.Result, flaggedCategory: Flipcash_Moderation_V1_FlaggedCategory) {
        switch result {
        case .ok:                   self = .unknown
        case .denied:               self = .denied
        case .chatNotSupported:     self = .chatNotSupported
        case .encryptionNotAllowed: self = .encryptionNotAllowed
        case .encryptionRequired:   self = .encryptionRequired
        case .invalidEndsAt:        self = .invalidEndsAt
        case .invalidShares:        self = .invalidShares
        case .invalidCurrency:      self = .invalidCurrency
        case .textModerated:        self = .textModerated(flaggedCategory)
        case .UNRECOGNIZED:         self = .unknown
        }
    }
}

extension ErrorCreatePaymentRequest: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .chatNotSupported, .encryptionNotAllowed, .encryptionRequired, .invalidEndsAt, .invalidShares, .invalidCurrency, .textModerated: .info
        case .unknown, .rejected: .error
        }
    }
}

public enum ErrorGetPaymentRequest: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorGetChatPaymentRequests: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorClosePaymentRequest: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorMarkPaid: Int, Error {
    case ok
    case denied
    case notFound
    case notOpen
    case notAShare
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorGetPaymentRequest: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetChatPaymentRequests: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorClosePaymentRequest: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorMarkPaid: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound, .notOpen, .notAShare: .info
        case .unknown, .rejected: .error
        }
    }
}
