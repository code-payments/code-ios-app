//
//  EmailService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCoreAPI
import GRPC

class EmailService: CodeService<Flipcash_Email_V1_EmailVerificationNIOClient> {
    
    func sendEmailVerification(email: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorSendEmailCode>) -> Void) {
        trace(.send, components: "Email: \(email)")
        
        let request = Flipcash_Email_V1_SendVerificationCodeRequest.with {
            $0.emailAddress = .with { $0.value = email }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.sendVerificationCode(request)
        call.handle(on: queue) { response in
            let error = ErrorSendEmailCode(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Email: \(email)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func checkEmailCode(email: String, code: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorCheckEmailCode>) -> Void) {
        trace(.send, components: "Email: \(email)", "Code: \(code)")
        
        let request = Flipcash_Email_V1_CheckVerificationCodeRequest.with {
            $0.emailAddress = .with { $0.value = email }
            $0.code = .with { $0.value = code }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.checkVerificationCode(request)
        call.handle(on: queue) { response in
            let error = ErrorCheckEmailCode(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Email: \(email)", "Code: \(code)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorSendEmailCode: Int, Error {
    case ok
    case denied
    /// Email is rate limited (eg. by IP, email address, user, etc) and was not sent.
    case rateLimited
    /// The email address is not real
    case invalidEmailAddress
    case unknown = -1
}

public enum ErrorCheckEmailCode: Int, Error {
    case ok
    case denied
    /// The call is rate limited (eg. by IP, email address, etc). The code is
    /// not verified.
    case rateLimited
    /// The provided verification code is invalid. The user may retry
    /// enterring the code if this is received. When max attempts are
    /// received, NO_VERIFICATION will be returned.
    case invalidCode
    /// There is no verification in progress for the email address. Several
    /// reasons this can occur include a verification being expired or having
    /// reached a maximum check threshold. The client must initiate a new
    /// verification using SendVerificationCode.
    case noVerification
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Email_V1_EmailVerificationClientInterceptorFactoryProtocol {
    func makeSendVerificationCodeInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Email_V1_SendVerificationCodeRequest, FlipcashCoreAPI.Flipcash_Email_V1_SendVerificationCodeResponse>] {
        makeInterceptors()
    }
    
    func makeCheckVerificationCodeInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Email_V1_CheckVerificationCodeRequest, FlipcashCoreAPI.Flipcash_Email_V1_CheckVerificationCodeResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Email_V1_EmailVerificationNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
