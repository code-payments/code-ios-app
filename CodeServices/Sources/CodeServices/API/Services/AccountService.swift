//
//  AccountService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Combine
import GRPC

class AccountService: CodeService<Code_Account_V1_AccountNIOClient> {
    
    func fetchIsCodeAccount(owner: KeyPair, completion: @escaping (Result<Bool, ErrorFetchIsCodeAccount>) -> Void) {
        trace(.send, components: owner.publicKey.base58)
        
        let request = Code_Account_V1_IsCodeAccountRequest.with {
            $0.owner = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.isCodeAccount(request)
        call.handle(on: queue) { response in
            
            let error = ErrorFetchIsCodeAccount(rawValue: response.result.rawValue) ?? .unknown
            switch error {
            case .ok:
                completion(.success(true))
            case .notFound:
                completion(.success(false))
            case .unlockedTimelock:
                completion(.success(false))
            case .unknown:
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchAccountInfos(owner: KeyPair, completion: @escaping (Result<[PublicKey: AccountInfo], ErrorFetchAccountInfos>) -> Void) {
//        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Code_Account_V1_GetTokenAccountInfosRequest.with {
            $0.owner = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getTokenAccountInfos(request)
        call.handle(on: queue) { response in
            
            let error = ErrorFetchAccountInfos(rawValue: response.result.rawValue)
            guard error == .ok else {
                trace(.failure, components: "Account not found for owner: \(owner.publicKey.base58)")
                completion(.failure(error))
                return
            }
            
            var container: [PublicKey: AccountInfo] = [:]
            do {
                try response.tokenAccountInfos.forEach { base58, tokenInfo in
                    
                    guard
                        let account = PublicKey(base58: base58),
                        let info = AccountInfo(tokenInfo)
                    else {
                        trace(.failure, components: "Failed to parse account info: \(tokenInfo)")
                        return
                    }
                    
                    guard tokenInfo.accountType != .legacyPrimary2022 else {
                        throw ErrorFetchAccountInfos.migrationRequired(info)
                    }
                    
                    container[account] = info
                }
                
            } catch ErrorFetchAccountInfos.migrationRequired(let info) {
                trace(.warning, components: "Owner requires migration: \(owner.publicKey.base58)")
                completion(.failure(.migrationRequired(info)))
                return
            } catch {}
            
//            trace(.success, components: container.map { "\($0.key.base58) | \($0.value.index) | \($0.value.balance) | \($0.value.accountType) | \($0.value.balanceSource) | \($0.value.managementState) | \($0.value.blockchainState)" })
//            trace(.success, components: "Fetched \(response.tokenAccountInfos.count) infos.")
            completion(.success(container))
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func linkAdditionalAccounts(owner: KeyPair, linkedAccount: KeyPair, completion: @escaping (Result<(), ErrorLinkAccounts>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Linked to: \(linkedAccount.publicKey.base58)")
        
        let request = Code_Account_V1_LinkAdditionalAccountsRequest.with {
            $0.owner = owner.publicKey.codeAccountID
            $0.swapAuthority = linkedAccount.publicKey.codeAccountID
            $0.signatures = [
                $0.sign(with: owner),
                $0.sign(with: linkedAccount),
            ]
        }
        
        let call = service.linkAdditionalAccounts(request)
        call.handle(on: queue) { response in
            
            let error = ErrorLinkAccounts(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Linked \(linkedAccount.publicKey.base58)")
                completion(.success(()))
            } else {
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorFetchIsCodeAccount: Int, Error {
    case ok
    case notFound
    case unlockedTimelock
    case unknown = -1
}

public enum ErrorFetchAccountInfos: Error, Equatable {
    case ok
    case notFound
    
    case unknown
    
    case migrationRequired(AccountInfo)
    
    init(rawValue: Int) {
        switch rawValue {
        case 0: self = .ok
        case 1: self = .notFound
        default:
            self = .unknown
        }
    }
}

public enum ErrorLinkAccounts: Int, Error {
    /// Supports idempotency, and will be returned as long as the request exactly
    /// matches a previous execution.
    case ok
    
    /// The action has been denied (eg. owner account not phone verified)
    case denied
    
    /// An account being linked is not valid
    case invalidAccount
    
    /// Unknown
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_Account_V1_AccountClientInterceptorFactoryProtocol {
    func makeIsCodeAccountInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Account_V1_IsCodeAccountRequest, CodeAPI.Code_Account_V1_IsCodeAccountResponse>] {
        makeInterceptors()
    }
    
    func makeGetTokenAccountInfosInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Account_V1_GetTokenAccountInfosRequest, CodeAPI.Code_Account_V1_GetTokenAccountInfosResponse>] {
        makeInterceptors()
    }
    
    func makeLinkAdditionalAccountsInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Account_V1_LinkAdditionalAccountsRequest, CodeAPI.Code_Account_V1_LinkAdditionalAccountsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Account_V1_AccountNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
