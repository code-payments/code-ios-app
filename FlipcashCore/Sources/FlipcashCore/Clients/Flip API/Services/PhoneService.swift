//
//  PhoneService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCoreAPI
import GRPC

private let logger = Logger(label: "flipcash.phone-service")

class PhoneService: CodeService<Flipcash_Phone_V1_PhoneVerificationNIOClient> {

    func sendVerificationCode(phone: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorSendVerificationCode>) -> Void) {
        logger.info("Sending phone verification code")

        let request = Flipcash_Phone_V1_SendVerificationCodeRequest.with {
            $0.platform = .apple
            $0.phoneNumber = .with { $0.value = phone }
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.sendVerificationCode(request)
        call.handle(on: queue) { response in
            let error = ErrorSendVerificationCode(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                logger.info("Phone verification code sent successfully")
                completion(.success(()))
            } else {
                logger.error("Failed to send phone verification code", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }

        } failure: { error in
            completion(.failure(.unknown))
        }
    }

    func checkVerificationCode(phone: String, code: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorCheckVerificationCode>) -> Void) {
        logger.info("Checking phone verification code")

        let request = Flipcash_Phone_V1_CheckVerificationCodeRequest.with {
            $0.phoneNumber = .with { $0.value = phone }
            $0.code = .with { $0.value = code }
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.checkVerificationCode(request)
        call.handle(on: queue) { response in
            let error = ErrorCheckVerificationCode(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                logger.info("Phone verification code accepted")
                completion(.success(()))
            } else {
                logger.error("Phone verification code check failed", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }

        } failure: { error in
            completion(.failure(.unknown))
        }
    }

    func unlinkPhone(phone: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorUnlinkPhone>) -> Void) {
        logger.info("Unlinking phone number")

        let request = Flipcash_Phone_V1_UnlinkRequest.with {
            $0.phoneNumber = .with { $0.value = phone }
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.unlink(request)
        call.handle(on: queue) { response in
            let error = ErrorUnlinkPhone(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                logger.info("Phone number unlinked successfully")
                completion(.success(()))
            } else {
                logger.error("Failed to unlink phone number", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }

        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorSendVerificationCode: Int, Error {
    case ok
    case denied
    /// SMS is rate limited (eg. by IP, phone number, user, etc) and was not sent.
    case rateLimited
    /// The phone number is not real because it fails Twilio lookup.
    case invalidPhoneNumber
    /// The phone number is valid, but it maps to an unsupported type of phone
    /// like a landline.
    case unsupportedPhoneType
    case unknown = -1
}

public enum ErrorCheckVerificationCode: Int, Error {
    case ok
    case denied
    /// The call is rate limited (eg. by IP, phone number, etc). The code is
    /// not verified.
    case rateLimited
    /// The provided verification code is invalid. The user may retry
    /// enterring the code if this is received. When max attempts are
    /// received, NO_VERIFICATION will be returned.
    case invalidCode
    /// There is no verification in progress for the phone number. Several
    /// reasons this can occur include a verification being expired or having
    /// reached a maximum check threshold. The client must initiate a new
    /// verification using SendVerificationCode.
    case noVerification
    case unknown = -1
}

public enum ErrorUnlinkPhone: Int, Error {
    case ok
    case denied
    case unknown = -1
}

extension ErrorSendVerificationCode: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .rateLimited, .invalidPhoneNumber, .unsupportedPhoneType: false
        case .unknown: true
        }
    }
}

extension ErrorCheckVerificationCode: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .rateLimited, .invalidCode, .noVerification: false
        case .unknown: true
        }
    }
}

extension ErrorUnlinkPhone: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied: false
        case .unknown: true
        }
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol {
    func makeUnlinkInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Phone_V1_UnlinkRequest, FlipcashCoreAPI.Flipcash_Phone_V1_UnlinkResponse>] {
        makeInterceptors()
    }
    
    func makeSendVerificationCodeInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Phone_V1_SendVerificationCodeRequest, FlipcashCoreAPI.Flipcash_Phone_V1_SendVerificationCodeResponse>] {
        makeInterceptors()
    }
    
    func makeCheckVerificationCodeInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Phone_V1_CheckVerificationCodeRequest, FlipcashCoreAPI.Flipcash_Phone_V1_CheckVerificationCodeResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Phone_V1_PhoneVerificationNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
