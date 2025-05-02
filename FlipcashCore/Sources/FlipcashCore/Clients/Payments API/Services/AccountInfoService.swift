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

final class AccountInfoService: CodeService<Code_Account_V1_AccountNIOClient> {
    func fetchAccountInfo(type: AccountInfoType, owner: KeyPair, completion: @Sendable @escaping (Result<AccountInfo, ErrorFetchBalance>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Code_Account_V1_GetTokenAccountInfosRequest.with {
            $0.owner = owner.publicKey.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getTokenAccountInfos(request)
        call.handle(on: queue) { response in
            
            let error = ErrorFetchBalance(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let account = response.tokenAccountInfos.compactMap {
                    if $0.value.accountType == type.proto, let account = try? AccountInfo($0.value) {
                        return account
                    } else {
                        return nil
                    }
                }.first
                
                if let account {
//                    let balance = Fiat(quarks: account.value.balance, currencyCode: .usd)
                    trace(.success, components: "Balance: \(account.fiat.formatted(suffix: " USD"))")
                    completion(.success(account))
                } else {
                    trace(.failure, components: "Account not in list of accounts returned: \(response.tokenAccountInfos)")
                    completion(.failure(error))
                }
                
            } else {
                trace(.failure, components: "Owner: \(owner.publicKey.base58)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Types -

public enum AccountInfoType: Sendable {
    case primary
    case giftCard
    
    fileprivate var proto: Code_Common_V1_AccountType {
        switch self {
        case .primary:  return .primary
        case .giftCard: return .remoteSendGiftCard
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
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_Account_V1_AccountClientInterceptorFactoryProtocol {
    func makeIsCodeAccountInterceptors() -> [GRPC.ClientInterceptor<Code_Account_V1_IsCodeAccountRequest, Code_Account_V1_IsCodeAccountResponse>] {
        makeInterceptors()
    }
    
    func makeGetTokenAccountInfosInterceptors() -> [GRPC.ClientInterceptor<Code_Account_V1_GetTokenAccountInfosRequest, Code_Account_V1_GetTokenAccountInfosResponse>] {
        makeInterceptors()
    }
    
    func makeLinkAdditionalAccountsInterceptors() -> [GRPC.ClientInterceptor<Code_Account_V1_LinkAdditionalAccountsRequest, Code_Account_V1_LinkAdditionalAccountsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Account_V1_AccountNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
