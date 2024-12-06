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
    
    func fetchProfile(userID: UserID, completion: @escaping (Result<String?, ErrorFetchProfile>) -> Void) {
        trace(.send, components: "User ID: \(userID.description)")
        
        let request = Flipchat_Profile_V1_GetProfileRequest.with {
            $0.userID = .with { $0.value = userID.data }
        }
        
        let call = service.getProfile(request)
        
        call.handle(on: queue) { response in
            let error = ErrorFetchProfile(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                let displayName = response.userProfile.displayName.isEmpty ? nil : response.userProfile.displayName
                completion(.success(displayName))
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

// MARK: - Interceptors -

extension InterceptorFactory: Flipchat_Profile_V1_ProfileClientInterceptorFactoryProtocol {
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
