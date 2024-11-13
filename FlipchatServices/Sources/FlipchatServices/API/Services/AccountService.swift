//
//  AccountService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI
import GRPC

class AccountService: FlipchatService<Flipchat_Account_V1_AccountNIOClient> {
    
    func register(name: String?, owner: KeyPair, completion: @escaping (Result<UserID, ErrorRegister>) -> Void) {
        trace(.send, components: "Name: \(name ?? "<empty>")", "Owner: \(owner.publicKey.base58)")
        
        let request = Flipchat_Account_V1_RegisterRequest.with {
            if let name {
                $0.displayName = name
            }
            
            $0.publicKey = owner.publicKey.protoPubKey
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.register(request)
        
        call.handle(on: queue) { response in
            let error = ErrorRegister(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let userID = UserID(data: response.userID.value)
                trace(.success, components: "User ID: \(userID.description)", "Name: \(name ?? "<empty>")", "Owner: \(owner.publicKey.base58)")
                completion(.success(userID))
                
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorRegister: Int, Error {
    case ok
    case invalidSignature
    case invalidDisplayName
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipchat_Account_V1_AccountClientInterceptorFactoryProtocol {
    func makeLoginInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Account_V1_LoginRequest, FlipchatAPI.Flipchat_Account_V1_LoginResponse>] {
        makeInterceptors()
    }
    
    func makeRegisterInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Account_V1_RegisterRequest, FlipchatAPI.Flipchat_Account_V1_RegisterResponse>] {
        makeInterceptors()
    }
    
    func makeAuthorizePublicKeyInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Account_V1_AuthorizePublicKeyRequest, FlipchatAPI.Flipchat_Account_V1_AuthorizePublicKeyResponse>] {
        makeInterceptors()
    }
    
    func makeRevokePublicKeyInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Account_V1_RevokePublicKeyRequest, FlipchatAPI.Flipchat_Account_V1_RevokePublicKeyResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipchat_Account_V1_AccountNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
