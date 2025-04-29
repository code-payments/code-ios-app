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
import NIO
import SwiftProtobuf

class ActivityService: CodeService<Flipcash_Activity_V1_ActivityFeedNIOClient> {
    
    func fetchTransactionHistory(owner: KeyPair, completion: @Sendable @escaping (Result<[Activity], ErrorFetchTransactionHistory>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Flipcash_Activity_V1_GetLatestNotificationsRequest.with {
            $0.type = .transactionHistory
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.getLatestNotifications(request)
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
                trace(.success)
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

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Activity_V1_ActivityFeedClientInterceptorFactoryProtocol {
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
