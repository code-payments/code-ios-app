//
//  AccountService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPC

private let logger = Logger(label: "flipcash.account-service")

class AccountService: CodeService<Flipcash_Account_V1_AccountNIOClient> {
    
    func register(owner: KeyPair, completion: @Sendable @escaping (Result<UserID, ErrorRegisterAccount>) -> Void) {
        logger.info("Registering account", metadata: ["owner": "\(owner.publicKey.base58)"])

        let request = Flipcash_Account_V1_RegisterRequest.with {
            $0.publicKey = owner.publicKey.proto
            $0.signature = $0.sign(with: owner)
        }

        let call = service.register(request)
        call.handle(on: queue, completion: completion) { response in
            let error = ErrorRegisterAccount(rawValue: response.result.rawValue) ?? .unknown
            guard error == .ok else {
                logger.error("Failed to register account", metadata: ["owner": "\(owner.publicKey.base58)"])
                return .failure(error)
            }
            let userID = try! UUID(data: response.userID.value)
            logger.info("Account registered successfully")
            return .success(userID)
        }
    }
    
    func login(owner: KeyPair, completion: @Sendable @escaping (Result<UserID, ErrorLoginAccount>) -> Void) {
        logger.info("Logging in", metadata: ["owner": "\(owner.publicKey.base58)"])

        let request = Flipcash_Account_V1_LoginRequest.with {
            $0.timestamp = .init(date: .now)
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.login(request)
        call.handle(on: queue, completion: completion) { response in
            let error = ErrorLoginAccount(rawValue: response.result.rawValue) ?? .unknown
            guard error == .ok else {
                logger.error("Failed to login", metadata: ["owner": "\(owner.publicKey.base58)"])
                return .failure(error)
            }
            let userID = try! UUID(data: response.userID.value)
            logger.info("Login succeeded")
            return .success(userID)
        }
    }
    
    func fetchUserFlags(userID: UserID, owner: KeyPair, completion: @Sendable @escaping (Result<UserFlags, ErrorFetchUserFlags>) -> Void) {
        logger.info("Fetching user flags", metadata: ["userId": "\(userID)"])

        let request = Flipcash_Account_V1_GetUserFlagsRequest.with {
            $0.userID = userID.proto
            $0.platform = .apple

            if let countryCode = Locale.current.region?.identifier {
//                $0.countryCode = .with { $0.value = "us"}
                $0.countryCode = .with { $0.value = countryCode }
            }

            $0.auth = owner.authFor(message: $0)
        }

        let call = service.getUserFlags(request)
        call.handle(on: queue, completion: completion) { response in
            let error = ErrorFetchUserFlags(rawValue: response.result.rawValue) ?? .unknown
            guard error == .ok else {
                logger.error("Failed to fetch user flags", metadata: ["owner": "\(owner.publicKey.base58)"])
                return .failure(error)
            }
            logger.info("User flags fetched successfully")
            return .success(UserFlags(response.userFlags))
        }
    }

    func fetchUnauthenticatedUserFlags(completion: @Sendable @escaping (Result<UnauthenticatedUserFlags, ErrorFetchUnauthenticatedUserFlags>) -> Void) {
        let request = Flipcash_Account_V1_GetUnauthenticatedUserFlagsRequest.with {
            $0.platform = .apple

            if let countryCode = Locale.current.region?.identifier {
                $0.countryCode = .with { $0.value = countryCode }
            }
        }

        let call = service.getUnauthenticatedUserFlags(request)
        call.handle(on: queue, completion: completion) { response in
            let error = ErrorFetchUnauthenticatedUserFlags(rawValue: response.result.rawValue) ?? .unknown
            guard error == .ok else {
                logger.error("Failed to fetch unauthenticated user flags")
                return .failure(error)
            }
            return .success(UnauthenticatedUserFlags(response.userFlags))
        }
    }
}

// MARK: - Errors -

public enum ErrorRegisterAccount: Int, Error, Equatable, Sendable {
    case ok
    case invalidSignature
    case denied
    case unknown          = -1
    case transportFailure = -2
}

public enum ErrorLoginAccount: Int, Error, Equatable, Sendable {
    case ok
    case invalidTimestamp
    case denied
    case unknown          = -1
    case transportFailure = -2
}

public enum ErrorFetchUserFlags: Int, Error, Equatable, Sendable {
    case ok
    case denied
    case unknown          = -1
    case transportFailure = -2
}

public enum ErrorFetchUnauthenticatedUserFlags: Int, Error, Equatable, Sendable {
    case ok
    case unknown          = -1
    case transportFailure = -2
}

extension ErrorRegisterAccount: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .invalidSignature, .denied, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorRegisterAccount: TransportClassifiableError {
    public static func from(transportError status: GRPCStatus) -> ErrorRegisterAccount {
        status.code.isTransientNetworkError ? .transportFailure : .unknown
    }
}

extension ErrorLoginAccount: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .invalidTimestamp, .denied, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorLoginAccount: TransportClassifiableError {
    public static func from(transportError status: GRPCStatus) -> ErrorLoginAccount {
        status.code.isTransientNetworkError ? .transportFailure : .unknown
    }
}

extension ErrorFetchUserFlags: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorFetchUserFlags: TransportClassifiableError {
    public static func from(transportError status: GRPCStatus) -> ErrorFetchUserFlags {
        status.code.isTransientNetworkError ? .transportFailure : .unknown
    }
}

extension ErrorFetchUnauthenticatedUserFlags: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorFetchUnauthenticatedUserFlags: TransportClassifiableError {
    public static func from(transportError status: GRPCStatus) -> ErrorFetchUnauthenticatedUserFlags {
        status.code.isTransientNetworkError ? .transportFailure : .unknown
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Account_V1_AccountClientInterceptorFactoryProtocol {
    func makeGetUnauthenticatedUserFlagsInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Account_V1_GetUnauthenticatedUserFlagsRequest, Flipcash_Account_V1_GetUnauthenticatedUserFlagsResponse>] {
        makeInterceptors()
    }
    
    func makeRegisterInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Account_V1_RegisterRequest, Flipcash_Account_V1_RegisterResponse>] {
        makeInterceptors()
    }
    
    func makeLoginInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Account_V1_LoginRequest, Flipcash_Account_V1_LoginResponse>] {
        makeInterceptors()
    }
    
    func makeGetUserFlagsInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Account_V1_GetUserFlagsRequest, Flipcash_Account_V1_GetUserFlagsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Account_V1_AccountNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
