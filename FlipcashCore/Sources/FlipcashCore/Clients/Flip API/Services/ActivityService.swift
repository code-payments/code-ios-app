//
//  ActivityService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.activity-service")

final class ActivityService: Sendable {

    private let service: Flipcash_Activity_V1_ActivityFeed.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Activity_V1_ActivityFeed.Client(wrapping: client)
    }

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

        Task {
            do {
                let response = try await service.getPagedNotifications(request, options: .unaryDefault)
                let error = ErrorFetchTransactionHistory(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch transaction history", metadata: ["owner": "\(owner.publicKey.base58)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
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
                await MainActor.run { completion(.success(activities)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func fetchTransactionHistoryItemsByID(owner: KeyPair, ids: [PublicKey], completion: @Sendable @escaping (Result<[Activity], ErrorFetchTransactionHistoryItemsByID>) -> Void) {
        logger.info("Fetching transaction history items by ID", metadata: ["owner": "\(owner.publicKey.base58)"])

        let request = Flipcash_Activity_V1_GetBatchNotificationsRequest.with {
            $0.ids = ids.map { id in .with { $0.value = id.data } }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getBatchNotifications(request, options: .unaryDefault)
                let error = ErrorFetchTransactionHistoryItemsByID(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch transaction history items", metadata: ["owner": "\(owner.publicKey.base58)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
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
                await MainActor.run { completion(.success(activities)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorFetchTransactionHistory: Int, Error {
    case ok
    case denied
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorFetchTransactionHistoryItemsByID: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorFetchTransactionHistory: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorFetchTransactionHistoryItemsByID: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}
