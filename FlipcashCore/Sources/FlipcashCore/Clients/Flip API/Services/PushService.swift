//
//  PushService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.push-service")

final class PushService: Sendable {

    private let service: Flipcash_Push_V1_Push.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Push_V1_Push.Client(wrapping: client)
    }

    func addToken(token: String, installationID: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorAddToken>) -> Void) {

        let request = Flipcash_Push_V1_AddTokenRequest.with {
            $0.tokenType  = .fcmApns
            $0.pushToken  = token
            $0.appInstall = .with { $0.value = installationID }
            $0.auth       = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.addToken(request, options: .unaryDefault)
                let error = ErrorAddToken(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to add push token", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
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

        Task {
            do {
                let response = try await service.deleteTokens(request, options: .unaryDefault)
                let error = ErrorDeleteToken(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to delete push tokens", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                logger.info("Push tokens deleted successfully")
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorAddToken: Int, Error {
    case ok
    case invalidPushToken
    case unknown          = -1
    case transportFailure = -2
}

public enum ErrorDeleteToken: Int, Error {
    case ok
    case unknown          = -1
    case transportFailure = -2
}

extension ErrorAddToken: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .invalidPushToken, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorDeleteToken: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .transportFailure: false
        case .unknown: true
        }
    }
}
