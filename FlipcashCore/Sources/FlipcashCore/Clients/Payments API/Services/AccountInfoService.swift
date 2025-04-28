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
    func fetchBalance(owner: KeyPair, completion: @Sendable @escaping (Result<Fiat, ErrorFetchBalance>) -> Void) {
//        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Code_Account_V1_GetTokenAccountInfosRequest.with {
            $0.owner = owner.publicKey.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getTokenAccountInfos(request)
        call.handle(on: queue) { response in
            if let account = response.tokenAccountInfos.filter({ $0.value.accountType == .primary }).first {
                let balance = Fiat(quarks: account.value.balance, currencyCode: .usd)
                completion(.success(balance))
            } else {
                completion(.failure(.notFound))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorFetchBalance: Int, Error, Equatable, Sendable {
    case ok
    case notFound
    case unknown = -1
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
