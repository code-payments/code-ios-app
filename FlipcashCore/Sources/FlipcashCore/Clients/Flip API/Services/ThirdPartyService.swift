//
//  ThirdPartyService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
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
        call.handle(on: queue, completion: completion) { response in
            let error = ErrorFetchJWT(rawValue: response.result.rawValue) ?? .unknown
            guard error == .ok else {
                logger.error("Failed to fetch Coinbase onramp JWT", metadata: ["error": "\(error)"])
                return .failure(error)
            }
            logger.info("Coinbase onramp JWT fetched successfully")
            return .success(response.jwt.value)
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
    case unknown          = -1
    case transportFailure = -2
}

extension ErrorFetchJWT: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .unsupportedProvider, .invalidApiKey, .phoneVerificationRequired, .emailVerificationRequired, .transportFailure: false
        case .unknown: true
        }
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Thirdparty_V1_ThirdPartyClientInterceptorFactoryProtocol {
    func makeGetJwtInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Thirdparty_V1_GetJwtRequest, Flipcash_Thirdparty_V1_GetJwtResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Thirdparty_V1_ThirdPartyNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
