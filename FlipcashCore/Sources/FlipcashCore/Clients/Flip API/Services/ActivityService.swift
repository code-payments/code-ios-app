//
//  ActivityService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPC

private let logger = Logger(label: "flipcash.activity-service")

class ActivityService: CodeService<Flipcash_Activity_V1_ActivityFeedNIOClient> {

    func fetchTransactionHistory(owner: KeyPair, pageSize: Int, since cursor: PublicKey?, completion: @Sendable @escaping (Result<[Activity], ErrorFetchTransactionHistory>) -> Void) {
        logger.info("Fetching transaction history", metadata: [
            "owner": "\(owner.publicKey.base58)",
            "cursor": "\(cursor?.base58 ?? "nil")"
        ])

        let request = Flipcash_Activity_V1_GetPagedNotificationsRequest.with {
            $0.type = .transactionHistory
            $0.queryOptions = .with {
                $0.order    = .asc
                $0.pageSize = Int32(pageSize)
                if let cursor {
                    $0.pagingToken = .with { $0.value = cursor.data }
                }
            }
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.getPagedNotifications(request)
        call.handle(on: queue, completion: completion) { response in
            let error = ErrorFetchTransactionHistory(rawValue: response.result.rawValue) ?? .unknown
            guard error == .ok else {
                logger.error("Failed to fetch transaction history", metadata: ["owner": "\(owner.publicKey.base58)"])
                return .failure(error)
            }
            let activities = response.notifications.compactMap {
                do {
                    return try Activity($0)
                } catch {
                    logger.error("Failed to parse activity", metadata: ["error": "\(error)"])
                    return nil
                }
            }
            logger.info("Fetched activities", metadata: ["count": "\(activities.count)"])
            return .success(activities)
        }
    }

    func fetchTransactionHistoryItemsByID(owner: KeyPair, ids: [PublicKey], completion: @Sendable @escaping (Result<[Activity], ErrorFetchTransactionHistoryItemsByID>) -> Void) {
        logger.info("Fetching transaction history items by ID", metadata: ["owner": "\(owner.publicKey.base58)"])

        let request = Flipcash_Activity_V1_GetBatchNotificationsRequest.with {
            $0.ids = ids.map { id in .with { $0.value = id.data } }
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.getBatchNotifications(request)
        call.handle(on: queue, completion: completion) { response in
            let error = ErrorFetchTransactionHistoryItemsByID(rawValue: response.result.rawValue) ?? .unknown
            guard error == .ok else {
                logger.error("Failed to fetch transaction history items", metadata: ["owner": "\(owner.publicKey.base58)"])
                return .failure(error)
            }
            let activities = response.notifications.compactMap {
                do {
                    return try Activity($0)
                } catch {
                    logger.error("Failed to parse activity", metadata: ["error": "\(error)"])
                    return nil
                }
            }
            logger.info("Fetched activities by ID", metadata: ["count": "\(activities.count)"])
            return .success(activities)
        }
    }
}

// MARK: - Errors -

public enum ErrorFetchTransactionHistory: Int, Error, Equatable, Sendable {
    case ok
    case denied
    case unknown          = -1
    case transportFailure = -2
}

public enum ErrorFetchTransactionHistoryItemsByID: Int, Error, Equatable, Sendable {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
}

extension ErrorFetchTransactionHistory: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorFetchTransactionHistory: TransportClassifiableError {
    public static func from(transportError status: GRPCStatus) -> ErrorFetchTransactionHistory {
        status.code.isTransientNetworkError ? .transportFailure : .unknown
    }
}

extension ErrorFetchTransactionHistoryItemsByID: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .notFound, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorFetchTransactionHistoryItemsByID: TransportClassifiableError {
    public static func from(transportError status: GRPCStatus) -> ErrorFetchTransactionHistoryItemsByID {
        status.code.isTransientNetworkError ? .transportFailure : .unknown
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Activity_V1_ActivityFeedClientInterceptorFactoryProtocol {
    func makeGetBatchNotificationsInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Activity_V1_GetBatchNotificationsRequest, Flipcash_Activity_V1_GetBatchNotificationsResponse>] {
        makeInterceptors()
    }
    
    func makeGetPagedNotificationsInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Activity_V1_GetPagedNotificationsRequest, Flipcash_Activity_V1_GetPagedNotificationsResponse>] {
        makeInterceptors()
    }
    
    func makeGetLatestNotificationsInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Activity_V1_GetLatestNotificationsRequest, Flipcash_Activity_V1_GetLatestNotificationsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Activity_V1_ActivityFeedNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
