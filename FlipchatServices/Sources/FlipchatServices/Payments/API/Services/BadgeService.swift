//
//  BadgeService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Combine
import GRPC

class BadgeService: CodeService<Code_Badge_V1_BadgeNIOClient> {
    
    func resetBadgeCount(owner: KeyPair, completion: @escaping (Result<Void, Error>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Code_Badge_V1_ResetBadgeCountRequest.with {
            $0.owner = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.resetBadgeCount(request)
        
        call.handle(on: queue) { response in
            if response.result == .ok {
                trace(.success, components: "Badges reset to 0 for owner: \(owner.publicKey.base58)")
                completion(.success(()))
            } else {
                trace(.failure)
                completion(.failure(ErrorGeneric.unknown))
            }
            
        } failure: { error in
            completion(.failure(ErrorGeneric.unknown))
        }
    }
}

// MARK: - Errors -

/// No custom errors yet

// MARK: - Interceptors -

extension InterceptorFactory: Code_Badge_V1_BadgeClientInterceptorFactoryProtocol {
    func makeResetBadgeCountInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Badge_V1_ResetBadgeCountRequest, CodeAPI.Code_Badge_V1_ResetBadgeCountResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Badge_V1_BadgeNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
