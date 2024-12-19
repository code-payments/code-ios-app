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
    
    // TODO: Remove `name`
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
    
    func login(owner: KeyPair, completion: @escaping (Result<UserID, ErrorLogin>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Flipchat_Account_V1_LoginRequest.with {
            $0.timestamp = .init(date: .now)
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.login(request)
        
        call.handle(on: queue) { response in
            let error = ErrorLogin(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let userID = UserID(data: response.userID.value)
                trace(.success, components: "User ID: \(userID.description)", "Owner: \(owner.publicKey.base58)")
                completion(.success(userID))
                
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchPaymentDestination(userID: UserID, completion: @escaping (Result<PublicKey, ErrorFetchPaymentDestination>) -> Void) {
        trace(.send, components: "User ID: \(userID.description)")
        
        let request = Flipchat_Account_V1_GetPaymentDestinationRequest.with {
            $0.userID = .with { $0.value = userID.data }
        }
        
        let call = service.getPaymentDestination(request)
        
        call.handle(on: queue) { response in
            let error = ErrorFetchPaymentDestination(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                guard let destination = PublicKey(response.paymentDestination.value) else {
                    completion(.failure(.failedToParsePublicKey))
                    return
                }
                
                trace(.success, components: "Destination: \(destination.base58)")
                completion(.success(destination))
                
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchUserFlags(userID: UserID, owner: KeyPair, completion: @escaping (Result<UserFlags, ErrorFetchUserFlags>) -> Void) {
        trace(.send, components: "User ID: \(userID.description)")
        
        let request = Flipchat_Account_V1_GetUserFlagsRequest.with {
            $0.userID = .with { $0.value = userID.data }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.getUserFlags(request)
        
        call.handle(on: queue) { response in
            let error = ErrorFetchUserFlags(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                guard let destination = PublicKey(response.userFlags.feeDestination.value) else {
                    completion(.failure(.failedToParsePublicKey))
                    return
                }
                
                let flags = UserFlags(
                    isStaff: response.userFlags.isStaff,
                    isRegistered: response.userFlags.isRegisteredAccount,
                    startGroupCost: Kin(quarks: response.userFlags.startGroupFee.quarks),
                    feeDestination: destination
                )
                
                trace(.success, components: "Is Staff: \(flags.isStaff ? "Yes" : "No")", "Start Group Cost: \(flags.startGroupCost.description)")
                completion(.success(flags))
                
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

public enum ErrorLogin: Int, Error {
    case ok
    case invalidTimestamp
    case denied
    case unknown = -1
}

public enum ErrorFetchPaymentDestination: Int, Error {
    case ok
    case notFound
    case unknown = -1
    case failedToParsePublicKey = -2
}

public enum ErrorFetchUserFlags: Int, Error {
    case ok
    case denied
    case unknown = -1
    case failedToParsePublicKey = -2
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipchat_Account_V1_AccountClientInterceptorFactoryProtocol {
    func makeGetUserFlagsInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Account_V1_GetUserFlagsRequest, FlipchatAPI.Flipchat_Account_V1_GetUserFlagsResponse>] {
        makeInterceptors()
    }
    
    func makeGetPaymentDestinationInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Account_V1_GetPaymentDestinationRequest, FlipchatAPI.Flipchat_Account_V1_GetPaymentDestinationResponse>] {
        makeInterceptors()
    }
    
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
