//
//  AccountService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCoreAPI
import GRPC

class AccountService: CodeService<Flipcash_Account_V1_AccountNIOClient> {
    
    func register(owner: KeyPair, completion: @Sendable @escaping (Result<UserID, ErrorRegisterAccount>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Flipcash_Account_V1_RegisterRequest.with {
            $0.publicKey = owner.publicKey.proto
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.register(request)
        call.handle(on: queue) { response in
            let error = ErrorRegisterAccount(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let userID = try! UUID(data: response.userID.value)
                trace(.success)
                completion(.success(userID))
            } else {
                trace(.failure, components: "Failed to register: \(owner.publicKey.base58)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func login(owner: KeyPair, completion: @Sendable @escaping (Result<UserID, ErrorLoginAccount>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Flipcash_Account_V1_LoginRequest.with {
            $0.timestamp = .init(date: .now)
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.login(request)
        call.handle(on: queue) { response in
            let error = ErrorLoginAccount(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let userID = try! UUID(data: response.userID.value)
                trace(.success)
                completion(.success(userID))
            } else {
                trace(.failure, components: "Failed to register: \(owner.publicKey.base58)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchUserFlags(userID: UserID, owner: KeyPair, completion: @Sendable @escaping (Result<UserFlags, ErrorFetchUserFlags>) -> Void) {
        trace(.send, components: "UserID: \(userID)")
        
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
        call.handle(on: queue) { response in
            let error = ErrorFetchUserFlags(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(UserFlags(response.userFlags)))
            } else {
                trace(.failure, components: "Failed to register: \(owner.publicKey.base58)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Types -

public struct UserFlags: Sendable {
    public let isRegistered: Bool
    public let isStaff: Bool
    public let onrampProviders: [OnRampProvider]
    public let preferredOnrampProvider: OnRampProvider
    
    public var hasPreferredOnrampProvider: Bool {
        preferredOnrampProvider != .unknown
    }
    
    public var hasCoinbase: Bool {
        onrampProviders.contains(.coinbaseVirtual) ||
        onrampProviders.contains(.coinbasePhysicalDebit) ||
        onrampProviders.contains(.coinbasePhysicalCredit)
    }
    
    public var hasPhantom: Bool {
        onrampProviders.contains(.phantom)
    }
    
    public var hasOtherCryptoWallets: Bool {
        onrampProviders.contains(.manualDeposit)
    }
}

extension UserFlags {
    public enum OnRampProvider: Int, Sendable {
        case unknown
        case coinbaseVirtual
        case coinbasePhysicalDebit
        case coinbasePhysicalCredit
        case manualDeposit
        case phantom
        case solflare
        case backpack
        case base
    }
        
    init(_ proto: Flipcash_Account_V1_UserFlags) {
        self.init(
            isRegistered: proto.isRegisteredAccount,
            isStaff: proto.isStaff,
            onrampProviders: proto.supportedOnRampProviders.map { OnRampProvider($0) },
            preferredOnrampProvider: OnRampProvider(proto.preferredOnRampProvider)
        )
    }
}

extension UserFlags.OnRampProvider {
    init(_ proto: Flipcash_Account_V1_UserFlags.OnRampProvider) {
        switch proto {
        case .unknown:
            self = .unknown
        case .coinbaseVirtual:
            self = .coinbaseVirtual
        case .coinbasePhysicalDebit:
            self = .coinbasePhysicalDebit
        case .coinbasePhysicalCredit:
            self = .coinbasePhysicalCredit
        case .manualDeposit:
            self = .manualDeposit
        case .phantom:
            self = .phantom
        case .solflare:
            self = .solflare
        case .backpack:
            self = .backpack
        case .base:
            self = .base
        case .UNRECOGNIZED:
            self = .unknown
        }
    }
}

// MARK: - Errors -

public enum ErrorRegisterAccount: Int, Error {
    case ok
    case invalidSignature
    case denied
    case unknown = -1
}

public enum ErrorLoginAccount: Int, Error {
    case ok
    case invalidTimestamp
    case denied
    case unknown = -1
}

public enum ErrorFetchUserFlags: Int, Error {
    case ok
    case denied
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Account_V1_AccountClientInterceptorFactoryProtocol {
    func makeGetUnauthenticatedUserFlagsInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Account_V1_GetUnauthenticatedUserFlagsRequest, FlipcashCoreAPI.Flipcash_Account_V1_GetUnauthenticatedUserFlagsResponse>] {
        makeInterceptors()
    }
    
    func makeRegisterInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Account_V1_RegisterRequest, FlipcashCoreAPI.Flipcash_Account_V1_RegisterResponse>] {
        makeInterceptors()
    }
    
    func makeLoginInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Account_V1_LoginRequest, FlipcashCoreAPI.Flipcash_Account_V1_LoginResponse>] {
        makeInterceptors()
    }
    
    func makeGetUserFlagsInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Account_V1_GetUserFlagsRequest, FlipcashCoreAPI.Flipcash_Account_V1_GetUserFlagsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Account_V1_AccountNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
