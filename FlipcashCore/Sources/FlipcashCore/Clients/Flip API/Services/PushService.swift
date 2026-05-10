//
//  PushService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPC

private let logger = Logger(label: "flipcash.push-service")

class PushService: CodeService<Flipcash_Push_V1_PushNIOClient> {

    func addToken(token: String, installationID: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorAddToken>) -> Void) {

        let request = Flipcash_Push_V1_AddTokenRequest.with {
            $0.tokenType  = .fcmApns
            $0.pushToken  = token
            $0.appInstall = .with { $0.value = installationID }
            $0.auth       = owner.authFor(message: $0)
        }

        let call = service.addToken(request)

        call.handle(on: queue) { response in
            let error = ErrorAddToken(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                completion(.success(()))
            } else {
                logger.error("Failed to add push token", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }

        } failure: { error in
            completion(.failure(.unknown))
        }
    }

    func deleteTokens(installationID: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorDeleteToken>) -> Void) {
        logger.info("Deleting push tokens", metadata: [
            "owner": "\(owner.publicKey.base58)",
            "installationId": "\(installationID)"
        ])

        let request = Flipcash_Push_V1_DeleteTokensRequest.with {
            $0.appInstall = .with { $0.value = installationID }
            $0.auth       = owner.authFor(message: $0)
        }

        let call = service.deleteTokens(request)

        call.handle(on: queue) { response in
            let error = ErrorDeleteToken(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                logger.info("Push tokens deleted successfully")
                completion(.success(()))
            } else {
                logger.error("Failed to delete push tokens", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }

        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorAddToken: Int, Error, Sendable {
    case ok
    case invalidPushToken
    case unknown = -1
}

public enum ErrorDeleteToken: Int, Error, Sendable {
    case ok
    case unknown = -1
}

extension ErrorAddToken: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .invalidPushToken: false
        case .unknown: true
        }
    }
}

extension ErrorDeleteToken: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok: false
        case .unknown: true
        }
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Push_V1_PushClientInterceptorFactoryProtocol {
    func makeAddTokenInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Push_V1_AddTokenRequest, Flipcash_Push_V1_AddTokenResponse>] {
        makeInterceptors()
    }
    
    func makeDeleteTokensInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Push_V1_DeleteTokensRequest, Flipcash_Push_V1_DeleteTokensResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Push_V1_PushNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
