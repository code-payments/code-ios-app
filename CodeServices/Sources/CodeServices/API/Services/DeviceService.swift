//
//  DeviceService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Combine
import GRPC

class DeviceService: CodeService<Code_Device_V1_DeviceNIOClient> {
    
    func registerInstallation(for owner: KeyPair, installationID: String, completion: @escaping (Result<Void, ErrorRegisterAccounts>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Installation: \(installationID)")
        
        let request = Code_Device_V1_RegisterLoggedInAccountsRequest.with {
            $0.appInstall = .with { $0.value = installationID }
            $0.owners = [
                owner.publicKey.codeAccountID
            ]
            $0.signatures = [
                $0.sign(with: owner)
            ]
        }
        
        let call = service.registerLoggedInAccounts(request)
        call.handle(on: queue) { response in
            let error = ErrorRegisterAccounts(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Registered installation: \(installationID)")
                completion(.success(()))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchInstallationAccounts(for installationID: String, completion: @escaping (Result<[PublicKey], ErrorFetchInstallationAccounts>) -> Void) {
        trace(.send, components: "Installation: \(installationID)")
        
        let request = Code_Device_V1_GetLoggedInAccountsRequest.with {
            $0.appInstall = .with { $0.value = installationID }
        }
        
        let call = service.getLoggedInAccounts(request)
        call.handle(on: queue) { response in
            let error = ErrorFetchInstallationAccounts(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let accounts = response.owners.compactMap {
                    PublicKey($0.value)
                }
                
                guard accounts.count == response.owners.count else {
                    completion(.failure(ErrorFetchInstallationAccounts.parseError))
                    return
                }
                
                trace(.success, components: "Fetched \(accounts.count) accounts")
                completion(.success(accounts))
                
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorRegisterAccounts: Int, Error {
    case ok
    case invalidOwner
    case unknown = -1
}

public enum ErrorFetchInstallationAccounts: Int, Error {
    case ok
    case unknown    = -1
    case parseError = -2
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_Device_V1_DeviceClientInterceptorFactoryProtocol {
    func makeRegisterLoggedInAccountsInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Device_V1_RegisterLoggedInAccountsRequest, CodeAPI.Code_Device_V1_RegisterLoggedInAccountsResponse>] {
        makeInterceptors()
    }
    
    func makeGetLoggedInAccountsInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Device_V1_GetLoggedInAccountsRequest, CodeAPI.Code_Device_V1_GetLoggedInAccountsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Device_V1_DeviceNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
