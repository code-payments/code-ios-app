//
//  ThirdPartyService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCoreAPI
import GRPC

class ThirdPartyService: CodeService<Flipcash_Thirdparty_V1_ThirdPartyNIOClient> {
    
    func fetchCoinbaseOnrampJWT(apiKey: String, owner: KeyPair, completion: @Sendable @escaping (Result<String, ErrorFetchJWT>) -> Void) {
        trace(.send)
        
        let request = Flipcash_Thirdparty_V1_GetJwtRequest.with {
            $0.apiKey = .with {
                $0.provider = .coinbase
                $0.value    = apiKey
            }
            $0.method = "POST"
            $0.host   = "api.cdp.coinbase.com/"
            $0.path   = "platform/v2/onramp/orders"
            $0.auth   = owner.authFor(message: $0)
        }
        
        let call = service.getJwt(request)
        call.handle(on: queue) { response in
            let error = ErrorFetchJWT(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(response.jwt.value))
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

public enum ErrorFetchJWT: Int, Error {
    case ok
    case denied
    case unsupportedProvider
    case invalidApiKey
    case phoneVerificationRequired
    case emailVerificationRequired
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Thirdparty_V1_ThirdPartyClientInterceptorFactoryProtocol {
    func makeGetJwtInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Thirdparty_V1_GetJwtRequest, FlipcashCoreAPI.Flipcash_Thirdparty_V1_GetJwtResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Thirdparty_V1_ThirdPartyNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
