//
//  ProfileService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCoreAPI
import GRPC

class ProfileService: CodeService<Flipcash_Profile_V1_ProfileNIOClient> {
    
    func fetchProfile(userID: UserID, owner: KeyPair, completion: @Sendable @escaping (Result<Profile, Error>) -> Void) {
        trace(.send, components: "User ID: \(userID)")
        
        let request = Flipcash_Profile_V1_GetProfileRequest.with {
            $0.userID = .with { $0.value = userID.data }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.getProfile(request)
        call.handle(on: queue) { response in
            let error = ErrorFetchProfile(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Email: \(response.userProfile.emailAddress.value)", "Phone: \(response.userProfile.phoneNumber.value)")
                do {
                    let profile = try Profile(response.userProfile)
                    completion(.success(profile))
                } catch {
                    completion(.failure(error))
                }
                
            } else if error == .notFound {
                trace(.success, components: "Empty profile")
                completion(.success(.empty))
                
            } else {
                trace(.failure, components: "User ID: \(userID)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(ErrorFetchProfile.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorFetchProfile: Int, Error {
    case ok
    case notFound
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Profile_V1_ProfileClientInterceptorFactoryProtocol {
    func makeGetProfileInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Profile_V1_GetProfileRequest, FlipcashCoreAPI.Flipcash_Profile_V1_GetProfileResponse>] {
        makeInterceptors()
    }
    
    func makeSetDisplayNameInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Profile_V1_SetDisplayNameRequest, FlipcashCoreAPI.Flipcash_Profile_V1_SetDisplayNameResponse>] {
        makeInterceptors()
    }
    
    func makeLinkSocialAccountInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Profile_V1_LinkSocialAccountRequest, FlipcashCoreAPI.Flipcash_Profile_V1_LinkSocialAccountResponse>] {
        makeInterceptors()
    }
    
    func makeUnlinkSocialAccountInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Profile_V1_UnlinkSocialAccountRequest, FlipcashCoreAPI.Flipcash_Profile_V1_UnlinkSocialAccountResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Profile_V1_ProfileNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
