//
//  EmailService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.email-service")

final class EmailService: Sendable {

    private let service: Flipcash_Email_V1_EmailVerification.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Email_V1_EmailVerification.Client(wrapping: client)
    }

    func sendEmailVerification(email: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorSendEmailCode>) -> Void) {
        logger.info("Sending email verification code")

        let request = Flipcash_Email_V1_SendVerificationCodeRequest.with {
            $0.emailAddress = .with { $0.value = email }
            $0.auth = owner.authFor(message: $0)
        }

        Task { @MainActor in
            do {
                let response = try await service.sendVerificationCode(request, options: .unaryDefault)
                let error = ErrorSendEmailCode(rawValue: response.result.rawValue) ?? .unknown
                if error == .ok {
                    logger.info("Email verification code sent successfully")
                    completion(.success(()))
                } else {
                    logger.error("Failed to send email verification code", metadata: ["error": "\(error)"])
                    completion(.failure(error))
                }
            } catch let error as RPCError {
                // PGV field validation surfaces as invalidArgument before the result handler runs.
                if error.code == .invalidArgument {
                    completion(.failure(.invalidEmailAddress))
                } else {
                    completion(.failure(.from(transportError: error)))
                }
            } catch {
                completion(.failure(.unknown))
            }
        }
    }

    func checkEmailCode(email: String, code: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorCheckEmailCode>) -> Void) {
        logger.info("Checking email verification code")

        let request = Flipcash_Email_V1_CheckVerificationCodeRequest.with {
            $0.emailAddress = .with { $0.value = email }
            $0.code = .with { $0.value = code }
            $0.auth = owner.authFor(message: $0)
        }

        Task { @MainActor in
            do {
                let response = try await service.checkVerificationCode(request, options: .unaryDefault)
                let error = ErrorCheckEmailCode(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Email verification code check failed", metadata: ["error": "\(error)"])
                    completion(.failure(error))
                    return
                }
                logger.info("Email verification code accepted")
                completion(.success(()))
            } catch let error as RPCError {
                completion(.failure(.from(transportError: error)))
            } catch {
                completion(.failure(.unknown))
            }
        }
    }

    func unlinkEmail(email: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorUnlinkEmail>) -> Void) {
        logger.info("Unlinking email address")

        let request = Flipcash_Email_V1_UnlinkRequest.with {
            $0.emailAddress = .with { $0.value = email }
            $0.auth = owner.authFor(message: $0)
        }

        Task { @MainActor in
            do {
                let response = try await service.unlink(request, options: .unaryDefault)
                let error = ErrorUnlinkEmail(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to unlink email address", metadata: ["error": "\(error)"])
                    completion(.failure(error))
                    return
                }
                logger.info("Email address unlinked successfully")
                completion(.success(()))
            } catch let error as RPCError {
                completion(.failure(.from(transportError: error)))
            } catch {
                completion(.failure(.unknown))
            }
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
    case transportFailure = -2
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
    case transportFailure = -2
}

public enum ErrorUnlinkEmail: Int, Error {
    case ok
    case denied
    case unknown = -1
    case transportFailure = -2
}

extension ErrorSendEmailCode: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .rateLimited, .invalidEmailAddress, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorCheckEmailCode: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .rateLimited, .invalidCode, .noVerification, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorUnlinkEmail: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .transportFailure: false
        case .unknown: true
        }
    }
}
