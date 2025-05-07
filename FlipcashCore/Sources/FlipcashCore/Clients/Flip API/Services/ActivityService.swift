//
//  ActivityService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCoreAPI
import GRPC

class ActivityService: CodeService<Flipcash_Activity_V1_ActivityFeedNIOClient> {
    
    func fetchTransactionHistory(owner: KeyPair, pageSize: Int, since cursor: PublicKey?, completion: @Sendable @escaping (Result<[Activity], ErrorFetchTransactionHistory>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Cursor: \(cursor?.base58 ?? "nil")")
        
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
        call.handle(on: queue) { response in
            let error = ErrorFetchTransactionHistory(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let activities = response.notifications.compactMap {
                    do {
                        return try Activity($0)
                    } catch {
                        trace(.failure, components: "Failed to parse activity: \($0)")
                        return nil
                    }
                }
                trace(.success, components: "Fetched \(activities.count) activities")
                completion(.success(activities))
            } else {
                trace(.failure, components: "Failed to register: \(owner.publicKey.base58)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchTransactionHistoryItemsByID(owner: KeyPair, ids: [PublicKey], completion: @Sendable @escaping (Result<[Activity], ErrorFetchTransactionHistoryItemsByID>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Flipcash_Activity_V1_GetBatchNotificationsRequest.with {
            $0.ids = ids.map { id in .with { $0.value = id.data } }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.getBatchNotifications(request)
        call.handle(on: queue) { response in
            let error = ErrorFetchTransactionHistoryItemsByID(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let activities = response.notifications.compactMap {
                    do {
                        return try Activity($0)
                    } catch {
                        trace(.failure, components: "Failed to parse activity: \($0)")
                        return nil
                    }
                }
                trace(.success, components: "Fetched \(activities.count) activities")
                completion(.success(activities))
            } else {
                trace(.failure, components: "Failed to register: \(owner.publicKey.base58)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorFetchTransactionHistory: Int, Error {
    case ok
    case denied
    case unknown = -1
}

public enum ErrorFetchTransactionHistoryItemsByID: Int, Error {
    case ok
    case denied
    case notFound
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Activity_V1_ActivityFeedClientInterceptorFactoryProtocol {
    func makeGetBatchNotificationsInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Activity_V1_GetBatchNotificationsRequest, FlipcashCoreAPI.Flipcash_Activity_V1_GetBatchNotificationsResponse>] {
        makeInterceptors()
    }
    
    func makeGetPagedNotificationsInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Activity_V1_GetPagedNotificationsRequest, FlipcashCoreAPI.Flipcash_Activity_V1_GetPagedNotificationsResponse>] {
        makeInterceptors()
    }
    
    func makeGetLatestNotificationsInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Activity_V1_GetLatestNotificationsRequest, FlipcashCoreAPI.Flipcash_Activity_V1_GetLatestNotificationsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Activity_V1_ActivityFeedNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
