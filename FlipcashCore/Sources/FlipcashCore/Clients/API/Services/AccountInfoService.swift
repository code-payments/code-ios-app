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
    
    
}

// MARK: - Errors -



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
