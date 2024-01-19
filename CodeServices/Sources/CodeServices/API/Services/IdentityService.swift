//
//  IdentityService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Combine
import GRPC

class IdentityService: CodeService<Code_User_V1_IdentityNIOClient> {
    
    func linkAccount(phone: Phone, code: String, owner: KeyPair, completion: @escaping (Result<Void, ErrorLinkAccount>) -> Void) {
        trace(.send, components: "Phone: \(phone)", "Code: \(code)", "Owner: \(owner.publicKey.base58)")
        
        let token = Code_Phone_V1_PhoneLinkingToken.with {
            $0.code = code.codeVerificationCode
            $0.phoneNumber = phone.codePhoneNumber
        }
        
        let request = Code_User_V1_LinkAccountRequest.with {
            $0.token = .phone(token)
            $0.ownerAccountID = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.linkAccount(request)
        
        call.handle(on: queue) { response in
            let error = ErrorLinkAccount(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Phone: \(phone)", "Code: \(code)", "Owner: \(owner.publicKey.base58)")
                completion(.success(()))
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func unlinkAccount(phone: Phone, owner: KeyPair, completion: @escaping (Result<Void, ErrorUnlinkAccount>) -> Void) {
        trace(.send, components: "Phone: \(phone)", "Owner: \(owner.publicKey.base58)")
        
        let request = Code_User_V1_UnlinkAccountRequest.with {
            $0.phoneNumber = phone.codePhoneNumber
            $0.ownerAccountID = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.unlinkAccount(request)
        
        call.handle(on: queue) { response in
            trace(.success, components: "Phone: \(phone)", "Owner: \(owner.publicKey.base58)")
            let error = ErrorUnlinkAccount(rawValue: response.result.rawValue) ?? .unknown
            if response.result == .ok {
                completion(.success(()))
            } else {
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchUser(phone: Phone, owner: KeyPair, completion: @escaping (Result<User, ErrorFetchUser>) -> Void) {
        trace(.send, components: "Phone: \(phone)", "Owner: \(owner.publicKey.base58)")
        
        let request = Code_User_V1_GetUserRequest.with {
            $0.phoneNumber = phone.codePhoneNumber
            $0.ownerAccountID = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getUser(request)
        
        call.handle(on: queue) { response in
            let error = ErrorFetchUser(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Phone: \(phone)", "Owner: \(owner.publicKey.base58)")
                let user = User(
                    codeUser: response.user,
                    containerID: response.dataContainerID,
                    betaFlagsAllowed: response.enableInternalFlags,
                    eligibleAirdrops: response.eligibleAirdrops
                )
                completion(.success(user))
                
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func loginToThirdParty(rendezvous: PublicKey, relationship: KeyPair, completion: @escaping (Result<Void, ErrorLoginToThirdParty>) -> Void) {
        trace(.send, components: "Rendezvous: \(rendezvous.base58)", "Relationship: \(relationship.publicKey.base58)")
        
        let request = Code_User_V1_LoginToThirdPartyAppRequest.with {
            $0.intentID = rendezvous.codeIntentID
            $0.userID = relationship.publicKey.codeAccountID
            $0.signature = $0.sign(with: relationship)
        }
        
        let call = service.loginToThirdPartyApp(request)
        
        call.handle(on: queue) { response in
            let error = ErrorLoginToThirdParty(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Relationship: \(relationship.publicKey.base58)")
                completion(.success(()))
                
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

public enum ErrorLinkAccount: Int, Error {
    case ok
    case invalidToken
    case rateLimited
    case unknown = -1
}

public enum ErrorUnlinkAccount: Int, Error {
    case ok
    case neverAssociated
    case unknown = -1
}

public enum ErrorFetchUser: Int, Error {
    case ok
    case notFound
    case notInvited
    case unlockedTimelock
    case unknown = -1
}

public enum ErrorLoginToThirdParty: Int, Error {
    case ok
    case requestNotFound
    case paymentRequired
    case loginNotSupported
    case differentLoginExists
    case invalidAccount
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_User_V1_IdentityClientInterceptorFactoryProtocol {
    func makeLoginToThirdPartyAppInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_User_V1_LoginToThirdPartyAppRequest, CodeAPI.Code_User_V1_LoginToThirdPartyAppResponse>] {
        makeInterceptors()
    }
    
    func makeGetLoginForThirdPartyAppInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_User_V1_GetLoginForThirdPartyAppRequest, CodeAPI.Code_User_V1_GetLoginForThirdPartyAppResponse>] {
        makeInterceptors()
    }
    
    func makeGetUserInterceptors() -> [ClientInterceptor<Code_User_V1_GetUserRequest, Code_User_V1_GetUserResponse>] {
        makeInterceptors()
    }
    
    func makeUnlinkAccountInterceptors() -> [ClientInterceptor<Code_User_V1_UnlinkAccountRequest, Code_User_V1_UnlinkAccountResponse>] {
        makeInterceptors()
    }
    
    func makeLinkAccountInterceptors() -> [ClientInterceptor<Code_User_V1_LinkAccountRequest, Code_User_V1_LinkAccountResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_User_V1_IdentityNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
