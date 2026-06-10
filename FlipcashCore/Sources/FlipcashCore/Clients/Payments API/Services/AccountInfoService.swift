//
//  AccountInfoService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import Combine
import GRPC

private let logger = Logger(label: "flipcash.account-info-service")

final class AccountInfoService: CodeService<Ocp_Account_V1_AccountNIOClient> {
    func fetchAccountInfo(type: AccountInfoType, owner: KeyPair, requestingOwner: KeyPair?, completion: @Sendable @escaping (Result<AccountInfo, ErrorFetchBalance>) -> Void) {
        var request = Ocp_Account_V1_GetTokenAccountInfosRequest()
        request.owner = owner.publicKey.solanaAccountID
        if let requestingOwner {
            request.requestingOwner = requestingOwner.publicKey.solanaAccountID
        }

        // Compute BOTH signatures against the unsigned message, then assign.
        // Assigning the first signature before computing the second would
        // change the serialized bytes the second sign() sees, and the server
        // would reject the request.
        let ownerSignature: Ocp_Common_V1_Signature = request.sign(with: owner)
        let requestingSignature: Ocp_Common_V1_Signature? = requestingOwner.map { request.sign(with: $0) }

        request.signature = ownerSignature
        if let requestingSignature {
            request.requestingOwnerSignature = requestingSignature
        }

        let call = service.getTokenAccountInfos(request)
        call.handle(on: queue) { response in
            
            let error = ErrorFetchBalance(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                switch Self.accountInfo(in: response, type: type) {
                case .success(let account):
                    completion(.success(account))
                case .failure(let failure):
                    logger.error("Account not in list of accounts returned", metadata: [
                        "expectedType": "\(type)",
                        "returnedCount": "\(response.tokenAccountInfos.count)",
                    ])
                    completion(.failure(failure))
                }

            } else {
                logger.error("Failed to fetch account info", metadata: ["owner": "\(owner.publicKey.base58)"])
                completion(.failure(error))
            }

        } failure: { error in
            completion(.failure(.from(transportError: error)))
        }
    }

    static func accountInfo(in response: Ocp_Account_V1_GetTokenAccountInfosResponse, type: AccountInfoType) -> Result<AccountInfo, ErrorFetchBalance> {
        let account = response.tokenAccountInfos.compactMap {
            if $0.value.accountType == type.proto, let account = try? AccountInfo($0.value) {
                return account
            } else {
                return nil
            }
        }.first

        if let account {
            return .success(account)
        } else {
            return .failure(.accountNotInList)
        }
    }

    /// Fetches the user's plain SPL associated token account for a specific
    /// mint via `GetTokenAccountInfos` with a server-side mint filter. Returns
    /// `nil` when no ATA exists yet (e.g. the user has never received this
    /// mint), which sweep callers treat as a zero balance.
    func fetchAssociatedTokenAccount(
        owner: KeyPair,
        mint: PublicKey,
        completion: @Sendable @escaping (Result<AccountInfo?, ErrorFetchBalance>) -> Void
    ) {
        let request = Ocp_Account_V1_GetTokenAccountInfosRequest.with {
            $0.owner = owner.publicKey.solanaAccountID
            $0.filterByMintAddress = mint.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }

        let call = service.getTokenAccountInfos(request)
        call.handle(on: queue) { response in
            let error = ErrorFetchBalance(rawValue: response.result.rawValue) ?? .unknown
            switch error {
            case .ok:
                let account = response.tokenAccountInfos.compactMap {
                    $0.value.accountType == .associatedTokenAccount ? (try? AccountInfo($0.value)) : nil
                }.first
                completion(.success(account))
            case .notFound:
                // No ATA for this mint yet — caller treats as zero balance.
                completion(.success(nil))
            case .unknown, .accountNotInList, .parseFailed, .transportFailure:
                logger.error("Failed to fetch associated token account", metadata: [
                    "owner": "\(owner.publicKey.base58)",
                    "mint": "\(mint.base58)",
                ])
                completion(.failure(error))
            }
        } failure: { error in
            completion(.failure(.from(transportError: error)))
        }
    }

    func fetchPrimaryAccounts(owner: KeyPair, completion: @Sendable @escaping (Result<[AccountInfo], ErrorFetchBalance>) -> Void) {
        let request = Ocp_Account_V1_GetTokenAccountInfosRequest.with {
            $0.owner = owner.publicKey.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getTokenAccountInfos(request)
        call.handle(on: queue) { response in
            let error = ErrorFetchBalance(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let accounts: [AccountInfo] = response.tokenAccountInfos.filter {
                    $0.value.accountType == .primary
                }.compactMap {
                    (try? AccountInfo($0.value))
                }
                
                completion(.success(accounts))
                
            } else {
                logger.error("Failed to fetch primary accounts", metadata: ["owner": "\(owner.publicKey.base58)"])
                completion(.failure(error))
            }

        } failure: { error in
            completion(.failure(.from(transportError: error)))
        }
    }

}

// MARK: - Types -

public enum AccountInfoType: Sendable {
    case primary
    case giftCard
    case pool
    
    fileprivate var proto: Ocp_Common_V1_AccountType {
        switch self {
        case .primary:  return .primary
        case .giftCard: return .remoteSendGiftCard
        case .pool:     return .pool
        }
    }
}

// MARK: - Errors -

public enum ErrorFetchBalance: Int, Error, Equatable, Sendable {
    case ok
    case notFound
    case unknown          = -1
    case accountNotInList = -2
    case parseFailed      = -3
    case transportFailure = -4
}

extension ErrorFetchBalance: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .notFound, .accountNotInList, .transportFailure: false
        case .unknown, .parseFailed: true
        }
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Ocp_Account_V1_AccountClientInterceptorFactoryProtocol {
    func makeGetTokenAccountInfosInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Account_V1_GetTokenAccountInfosRequest, FlipcashAPI.Ocp_Account_V1_GetTokenAccountInfosResponse>] {
        makeInterceptors()
    }
    
    func makeIsOcpAccountInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Account_V1_IsOcpAccountRequest, FlipcashAPI.Ocp_Account_V1_IsOcpAccountResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Ocp_Account_V1_AccountNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
