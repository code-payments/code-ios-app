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

class ProfileService: FlipchatService<Flipchat_Profile_V1_ProfileNIOClient> {
    
    func fetchProfile(userID: UserID, completion: @escaping (Result<UserProfile, ErrorFetchProfile>) -> Void) {
        trace(.send, components: "User ID: \(userID.description)")
        
        let request = Flipchat_Profile_V1_GetProfileRequest.with {
            $0.userID = .with { $0.value = userID.data }
        }
        
        let call = service.getProfile(request)
        
        call.handle(on: queue) { response in
            let error = ErrorFetchProfile(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                let profile = UserProfile(response.userProfile)
                completion(.success(profile))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func setDisplayName(name: String, owner: KeyPair, completion: @escaping (Result<(), ErrorSetDisplayName>) -> Void) {
        trace(.send, components: "Name: \(name)")
        
        let request = Flipchat_Profile_V1_SetDisplayNameRequest.with {
            $0.displayName = name
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.setDisplayName(request)
        
        call.handle(on: queue) { response in
            let error = ErrorSetDisplayName(rawValue: response.result.rawValue) ?? .unknown
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
    
    func linkSocialAccount(token: String, owner: KeyPair, completion: @escaping (Result<Chat.SocialProfile, ErrorLinkSocialAccount>) -> Void) {
        trace(.send, components: "Token: \(token)")
        
        let request = Flipchat_Profile_V1_LinkSocialAccountRequest.with {
            $0.linkingToken = .with {
                $0.x = .with { $0.accessToken = token }
            }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.linkSocialAccount(request)
        
        call.handle(on: queue) { response in
            let error = ErrorLinkSocialAccount(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                if let profile = Chat.SocialProfile(response.socialProfile) {
                    trace(.success)
                    completion(.success(profile))
                } else {
                    trace(.failure)
                    completion(.failure(.failedToParse))
                }
                
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func unlinkSocialAccount(socialID: String, owner: KeyPair, completion: @escaping (Result<(), ErrorUnlinkSocialAccount>) -> Void) {
        trace(.send, components: "Social ID: \(socialID)")
        
        let request = Flipchat_Profile_V1_UnlinkSocialAccountRequest.with {
            $0.xUserID = socialID
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.unlinkSocialAccount(request)
        
        call.handle(on: queue) { response in
            let error = ErrorUnlinkSocialAccount(rawValue: response.result.rawValue) ?? .unknown
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

public enum ErrorFetchProfile: Int, Error {
    case ok
    case notFound
    case unknown = -1
}

public enum ErrorSetDisplayName: Int, Error {
    case ok
    case invalidDisplayName
    case denied
    case unknown = -1
}

public enum ErrorLinkSocialAccount: Int, Error {
    case ok
    case invalidLinkingToken
    case existingLink
    case denied
    case unknown = -1
    case failedToParse = -2
}

public enum ErrorUnlinkSocialAccount: Int, Error {
    case ok
    case denied
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipchat_Profile_V1_ProfileClientInterceptorFactoryProtocol {
    func makeLinkSocialAccountInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Profile_V1_LinkSocialAccountRequest, FlipchatAPI.Flipchat_Profile_V1_LinkSocialAccountResponse>] {
        makeInterceptors()
    }
    
    func makeUnlinkSocialAccountInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Profile_V1_UnlinkSocialAccountRequest, FlipchatAPI.Flipchat_Profile_V1_UnlinkSocialAccountResponse>] {
        makeInterceptors()
    }
    
    
    func makeGetProfileInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Profile_V1_GetProfileRequest, FlipchatAPI.Flipchat_Profile_V1_GetProfileResponse>] {
        makeInterceptors()
    }
    
    func makeSetDisplayNameInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Profile_V1_SetDisplayNameRequest, FlipchatAPI.Flipchat_Profile_V1_SetDisplayNameResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipchat_Profile_V1_ProfileNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
