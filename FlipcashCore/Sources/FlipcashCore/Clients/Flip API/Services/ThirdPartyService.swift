//
//  ThirdPartyService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.third-party-service")

final class ThirdPartyService: Sendable {

    private let service: Flipcash_Thirdparty_V1_ThirdParty.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Thirdparty_V1_ThirdParty.Client(wrapping: client)
    }

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

        Task { @MainActor in
            do {
                let response = try await service.getJwt(request, options: .unaryDefault)
                let error = ErrorFetchJWT(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch Coinbase onramp JWT", metadata: ["error": "\(error)"])
                    completion(.failure(error))
                    return
                }
                logger.info("Coinbase onramp JWT fetched successfully")
                completion(.success(response.jwt.value))
            } catch let error as RPCError {
                completion(.failure(.from(transportError: error)))
            } catch {
                completion(.failure(.unknown))
            }
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
