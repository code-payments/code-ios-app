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
import SwiftProtobuf

class PoolService: CodeService<Flipcash_Pool_V1_PoolNIOClient> {
    
    // MARK: - Pools -
    
    func fetchPools(owner: KeyPair, pageSize: Int, since cursor: ID?, completion: @Sendable @escaping (Result<[PoolDescription], ErrorFetchPools>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Cursor: \(cursor?.data.hexString() ?? "nil")")
        
        let request = Flipcash_Pool_V1_GetPagedPoolsRequest.with {
            $0.queryOptions = .with {
                $0.order    = .asc
                $0.pageSize = Int32(pageSize)
                if let cursor {
                    $0.pagingToken = .with { $0.value = cursor.data }
                }
            }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.getPagedPools(request)
        call.handle(on: queue) { response in
            let error = ErrorFetchPools(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let pools = response.pools.compactMap {
                    try? PoolDescription($0)
                }
                trace(.success, components: "Fetched \(pools.count) pools")
                completion(.success(pools))
            } else {
                trace(.failure, components: "Failed to fetch pools: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchPool(poolID: PublicKey, completion: @Sendable @escaping (Result<PoolDescription, Error>) -> Void) {
        trace(.send, components: "Pool ID: \(poolID.base58)")
        
        let request = Flipcash_Pool_V1_GetPoolRequest.with {
            $0.id = .with { $0.value = poolID.data }
        }
        
        let call = service.getPool(request)
        call.handle(on: queue) { response in
            let error = ErrorFetchPool(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                do {
                    let description = try PoolDescription(response.pool)
                    trace(.success)
                    completion(.success(description))
                } catch {
                    trace(.failure, components: "Pool ID: \(poolID.base58)", "Error: \(error)")
                    completion(.failure(error))
                }
            } else {
                trace(.failure, components: "Pool ID: \(poolID.base58)", "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(ErrorFetchPool.unknown))
        }
    }
    
    func createPool(poolMetadata: PoolMetadata, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorCreatePool>) -> Void) {
        guard let rendezvous = poolMetadata.rendezvous else {
            completion(.failure(.poolMetadataMissingRendezvous))
            return
        }
        
        trace(.send, components: "Pool ID: \(poolMetadata.id.base58)")
        
        let request = Flipcash_Pool_V1_CreatePoolRequest.with {
            $0.pool = poolMetadata.signedMetadata
            $0.rendezvousSignature = $0.pool.sign(with: rendezvous)
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.createPool(request)
        call.handle(on: queue) { response in
            let error = ErrorCreatePool(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Pool ID: \(poolMetadata.id.base58)", "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func closePool(poolMetadata: PoolMetadata, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorClosePool>) -> Void) {
        guard let rendezvous = poolMetadata.rendezvous else {
            completion(.failure(.poolMetadataMissingRendezvous))
            return
        }
        
        trace(.send, components: "Pool ID: \(poolMetadata.id.base58)")
        
        let request = Flipcash_Pool_V1_ClosePoolRequest.with {
            $0.id = .with { $0.value = poolMetadata.id.data }
            if let closedDate = poolMetadata.closedDate {
                $0.closedAt = .from(date: closedDate, stripNanos: true)
            }
            let proto = poolMetadata.signedMetadata
            $0.newRendezvousSignature = proto.sign(with: rendezvous)
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.closePool(request)
        call.handle(on: queue) { response in
            let error = ErrorClosePool(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Pool ID: \(poolMetadata.id.base58)", "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func resolvePool(poolMetadata: PoolMetadata, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorResolvePool>) -> Void) {
        guard let rendezvous = poolMetadata.rendezvous else {
            completion(.failure(.poolMetadataMissingRendezvous))
            return
        }
        
        trace(.send, components: "Pool ID: \(poolMetadata.id.base58)")
        
        let request = Flipcash_Pool_V1_ResolvePoolRequest.with {
            $0.id = .with { $0.value = poolMetadata.id.data }
            if let resolution = poolMetadata.resolution {
                $0.resolution = resolution.proto
            }
            $0.newRendezvousSignature = poolMetadata.signedMetadata.sign(with: rendezvous)
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.resolvePool(request)
        call.handle(on: queue) { response in
            let error = ErrorResolvePool(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Pool ID: \(poolMetadata.id.base58)", "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    // MARK: - Bet -
    
    func createBet(poolRendezvous: KeyPair, betMetadata: BetMetadata, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorCreateBet>) -> Void) {
        trace(.send, components: "Pool ID: \(poolRendezvous.publicKey.base58)", "Bet: \(betMetadata.selectedOutcome)")
        
        let request = Flipcash_Pool_V1_MakeBetRequest.with {
            $0.poolID = .with { $0.value = poolRendezvous.publicKey.data }
            $0.bet = .with {
                $0.betID             = .with { $0.value = betMetadata.id.data }
                $0.userID            = betMetadata.userID.proto
                $0.selectedOutcome   = .with { $0.booleanOutcome = betMetadata.selectedOutcome.boolValue! }
                $0.payoutDestination = betMetadata.payoutDestination.proto
                $0.ts                = .now
            }
            
            $0.rendezvousSignature = $0.bet.sign(with: poolRendezvous)
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.makeBet(request)
        call.handle(on: queue) { response in
            let error = ErrorCreateBet(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Pool ID: \(poolRendezvous.publicKey.base58)", "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Extensions -

extension Google_Protobuf_Timestamp {
    static var now: Google_Protobuf_Timestamp {
        .from(date: .now, stripNanos: true)
    }
    
    static func from(date: Date, stripNanos: Bool) -> Self {
        var ts = Google_Protobuf_Timestamp(date: date)
        if stripNanos {
            ts.nanos = 0
        }
        return ts
    }
}

// MARK: - Errors -

public enum ErrorFetchPools: Int, Error {
    case ok
    case notFound
    case unknown = -1
    case failedToParsePool = -2
}

public enum ErrorFetchPool: Int, Error {
    case ok
    case notFound
    case unknown = -1
}

public enum ErrorCreatePool: Int, Error {
    case ok
    case rendezvousExists
    case fundingDestinationExists
    case unknown = -1
    case poolMetadataMissingRendezvous = -2
}

public enum ErrorClosePool: Int, Error {
    case ok
    case denied
    case notFound
    case unknown = -1
    case poolMetadataMissingRendezvous = -2
}

public enum ErrorResolvePool: Int, Error {
    case ok
    case denied
    case notFound
    case differentOutcomeDeclared
    case poolOpen
    case unknown = -1
    case poolMetadataMissingRendezvous = -2
}

public enum ErrorCreateBet: Int, Error {
    case ok
    case poolNotFound
    case poolClosed
    case multipleBets
    case maxBetsReceived
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Pool_V1_PoolClientInterceptorFactoryProtocol {
    func makeGetPagedPoolsInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Pool_V1_GetPagedPoolsRequest, FlipcashCoreAPI.Flipcash_Pool_V1_GetPagedPoolsResponse>] {
        makeInterceptors()
    }
    
    func makeClosePoolInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Pool_V1_ClosePoolRequest, FlipcashCoreAPI.Flipcash_Pool_V1_ClosePoolResponse>] {
        makeInterceptors()
    }
    
    func makeCreatePoolInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Pool_V1_CreatePoolRequest, FlipcashCoreAPI.Flipcash_Pool_V1_CreatePoolResponse>] {
        makeInterceptors()
    }
    
    func makeGetPoolInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Pool_V1_GetPoolRequest, FlipcashCoreAPI.Flipcash_Pool_V1_GetPoolResponse>] {
        makeInterceptors()
    }
    
    func makeResolvePoolInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Pool_V1_ResolvePoolRequest, FlipcashCoreAPI.Flipcash_Pool_V1_ResolvePoolResponse>] {
        makeInterceptors()
    }
    
    func makeMakeBetInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Pool_V1_MakeBetRequest, FlipcashCoreAPI.Flipcash_Pool_V1_MakeBetResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Pool_V1_PoolNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
