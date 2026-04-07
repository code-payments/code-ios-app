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

private let logger = Logger(label: "flipcash.third-party-service")

class ThirdPartyService: CodeService<Flipcash_Thirdparty_V1_ThirdPartyNIOClient> {

    func fetchCoinbaseOnrampJWT(apiKey: String, owner: KeyPair, method: String, path: String, completion: @Sendable @escaping (Result<String, ErrorFetchJWT>) -> Void) {
        logger.info("Fetching Coinbase onramp JWT", metadata: [
            "method": "\(method)",
            "path": "\(path)"
        ])

        let request = Flipcash_Thirdparty_V1_GetJwtRequest.with {
            $0.apiKey = .with {
                $0.provider = .coinbase
                $0.value    = apiKey
            }
            $0.method = method
            $0.host   = "api.cdp.coinbase.com/"
            $0.path   = path
            $0.auth   = owner.authFor(message: $0)
        }

        let call = service.getJwt(request)
        call.handle(on: queue) { response in
            let error = ErrorFetchJWT(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                logger.info("Coinbase onramp JWT fetched successfully")
                completion(.success(response.jwt.value))
            } else {
                logger.error("Failed to fetch Coinbase onramp JWT: \(error)")
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
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
