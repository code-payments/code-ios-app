//
//  AccountService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.account-service")

final class AccountService: Sendable {

    private let service: Flipcash_Account_V1_Account.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Account_V1_Account.Client(wrapping: client)
    }

    func register(owner: KeyPair, completion: @Sendable @escaping (Result<UserID, ErrorRegisterAccount>) -> Void) {
        logger.info("Registering account", metadata: ["owner": "\(owner.publicKey.base58)"])

        let request = Flipcash_Account_V1_RegisterRequest.with {
            $0.publicKey = owner.publicKey.proto
            $0.signature = $0.sign(with: owner)
        }

        Task {
            do {
                let response = try await service.register(request, options: .unaryDefault)
                let error = ErrorRegisterAccount(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to register account", metadata: ["owner": "\(owner.publicKey.base58)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                guard let userID = try? UUID(data: response.userID.value) else {
                    logger.error("Registered account returned an unparseable user ID", metadata: ["owner": "\(owner.publicKey.base58)"])
                    await MainActor.run { completion(.failure(.unknown)) }
                    return
                }
                logger.info("Account registered successfully")
                await MainActor.run { completion(.success(userID)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func login(owner: KeyPair, completion: @Sendable @escaping (Result<UserID, ErrorLoginAccount>) -> Void) {
        logger.info("Logging in", metadata: ["owner": "\(owner.publicKey.base58)"])

        let request = Flipcash_Account_V1_LoginRequest.with {
            $0.timestamp = .init(date: .now)
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.login(request, options: .unaryDefault)
                let error = ErrorLoginAccount(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to login", metadata: ["owner": "\(owner.publicKey.base58)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                guard let userID = try? UUID(data: response.userID.value) else {
                    logger.error("Login returned an unparseable user ID", metadata: ["owner": "\(owner.publicKey.base58)"])
                    await MainActor.run { completion(.failure(.unknown)) }
                    return
                }
                logger.info("Login succeeded")
                await MainActor.run { completion(.success(userID)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func fetchUserFlags(userID: UserID, owner: KeyPair, timeout: TimeInterval? = nil, completion: @Sendable @escaping (Result<UserFlags, ErrorFetchUserFlags>) -> Void) {
        logger.info("Fetching user flags", metadata: ["userId": "\(userID)"])

        let request = Flipcash_Account_V1_GetUserFlagsRequest.with {
            $0.userID = userID.proto
            $0.platform = .apple

            if let countryCode = Locale.current.region?.identifier {
                $0.countryCode = .with { $0.value = countryCode }
            }

            $0.auth = owner.authFor(message: $0)
        }

        var options = CallOptions.unaryDefault
        if let timeout {
            options.timeout = .seconds(timeout)
        }

        Task {
            do {
                let response = try await service.getUserFlags(request, options: options)
                let error = ErrorFetchUserFlags(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch user flags", metadata: ["owner": "\(owner.publicKey.base58)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                logger.info("User flags fetched successfully")
                await MainActor.run { completion(.success(UserFlags(response.userFlags))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func fetchUnauthenticatedUserFlags(completion: @Sendable @escaping (Result<UnauthenticatedUserFlags, ErrorFetchUnauthenticatedUserFlags>) -> Void) {
        let request = Flipcash_Account_V1_GetUnauthenticatedUserFlagsRequest.with {
            $0.platform = .apple

            if let countryCode = Locale.current.region?.identifier {
                $0.countryCode = .with { $0.value = countryCode }
            }
        }

        Task {
            do {
                let response = try await service.getUnauthenticatedUserFlags(request, options: .unaryDefault)
                let error = ErrorFetchUnauthenticatedUserFlags(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch unauthenticated user flags")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                await MainActor.run { completion(.success(UnauthenticatedUserFlags(response.userFlags))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorRegisterAccount: Int, Error {
    case ok
    case invalidSignature
    case denied
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorLoginAccount: Int, Error {
    case ok
    case invalidTimestamp
    case denied
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorFetchUserFlags: Int, Error {
    case ok
    case denied
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorFetchUnauthenticatedUserFlags: Int, Error {
    case ok
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorRegisterAccount: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .invalidSignature, .denied: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorLoginAccount: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .invalidTimestamp, .denied: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorFetchUserFlags: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorFetchUnauthenticatedUserFlags: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .unknown, .rejected: .error
        }
    }
}
