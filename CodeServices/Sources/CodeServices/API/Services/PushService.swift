//
//  PushService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Combine
import GRPC

class PushService: CodeService<Code_Push_V1_PushNIOClient> {
    func addToken(firebaseToken: String, containerID: ID, owner: KeyPair, completion: @escaping (Result<Void, ErrorAddToken>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        var request = Code_Push_V1_AddTokenRequest()
        request.pushToken = firebaseToken
        request.containerID = containerID.codeContainerID
        request.ownerAccountID = owner.publicKey.codeAccountID
        request.tokenType = .fcmApns
        request.signature = request.sign(with: owner)
        
        let call = service.addToken(request)
        call.handle(on: queue) { response in
            let error = ErrorAddToken(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Firebase Token: \(firebaseToken)")
                completion(.success(()))
            } else {
                trace(.failure, components: "Firebase Token: \(firebaseToken)", "Error: \(error)")
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

// MARK: - Interceptors -

extension InterceptorFactory: Code_Push_V1_PushClientInterceptorFactoryProtocol {
    func makeAddTokenInterceptors() -> [ClientInterceptor<Code_Push_V1_AddTokenRequest, Code_Push_V1_AddTokenResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Push_V1_PushNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
