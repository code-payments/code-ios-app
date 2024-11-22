//
//  PushService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI
import GRPC

class PushService: FlipchatService<Flipchat_Push_V1_PushNIOClient> {
    
    func addToken(token: String, installationID: String, owner: KeyPair, completion: @escaping (Result<(), ErrorAddToken>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Token: \(token)", "Install ID: \(installationID)")
        
        let request = Flipchat_Push_V1_AddTokenRequest.with {
            $0.tokenType = .fcmApns
            $0.pushToken = token
            $0.appInstall = .with { $0.value = installationID }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.addToken(request)
        
        call.handle(on: queue) { response in
            let error = ErrorAddToken(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func deleteToken(token: String, owner: KeyPair, completion: @escaping (Result<(), ErrorDeleteToken>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Token: \(token)")
        
        let request = Flipchat_Push_V1_DeleteTokenRequest.with {
            $0.tokenType = .fcmApns
            $0.pushToken = token
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.deleteToken(request)
        
        call.handle(on: queue) { response in
            let error = ErrorDeleteToken(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorAddToken: Int, Error {
    case ok
    case invalidPushToken
    case unknown = -1
}

public enum ErrorDeleteToken: Int, Error {
    case ok
    case unknown = -1
}


// MARK: - Interceptors -

extension InterceptorFactory: Flipchat_Push_V1_PushClientInterceptorFactoryProtocol {
    func makeAddTokenInterceptors() -> [ClientInterceptor<Flipchat_Push_V1_AddTokenRequest, Flipchat_Push_V1_AddTokenResponse>] {
        makeInterceptors()
    }
    
    func makeDeleteTokenInterceptors() -> [ClientInterceptor<Flipchat_Push_V1_DeleteTokenRequest, Flipchat_Push_V1_DeleteTokenResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipchat_Push_V1_PushNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
