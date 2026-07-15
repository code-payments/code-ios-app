//
//  PhoneService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.phone-service")

final class PhoneService: Sendable {

    private let service: Flipcash_Phone_V1_PhoneVerification.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Phone_V1_PhoneVerification.Client(wrapping: client)
    }

    func sendVerificationCode(phone: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorSendVerificationCode>) -> Void) {
        logger.info("Sending phone verification code")

        let request = Flipcash_Phone_V1_SendVerificationCodeRequest.with {
            $0.platform = .apple
            $0.phoneNumber = .with { $0.value = phone }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.sendVerificationCode(request, options: .unaryDefault)
                let error = ErrorSendVerificationCode(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to send phone verification code", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                logger.info("Phone verification code sent successfully")
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func checkVerificationCode(phone: String, code: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorCheckVerificationCode>) -> Void) {
        logger.info("Checking phone verification code")

        let request = Flipcash_Phone_V1_CheckVerificationCodeRequest.with {
            $0.phoneNumber = .with { $0.value = phone }
            $0.code = .with { $0.value = code }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.checkVerificationCode(request, options: .unaryDefault)
                let error = ErrorCheckVerificationCode(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Phone verification code check failed", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                logger.info("Phone verification code accepted")
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func unlinkPhone(phone: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorUnlinkPhone>) -> Void) {
        logger.info("Unlinking phone number")

        let request = Flipcash_Phone_V1_UnlinkRequest.with {
            $0.phoneNumber = .with { $0.value = phone }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.unlink(request, options: .unaryDefault)
                let error = ErrorUnlinkPhone(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to unlink phone number", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                logger.info("Phone number unlinked successfully")
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func linkForPayment(phone: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorLinkForPayment>) -> Void) {
        logger.info("Linking phone number for payment")

        let request = Flipcash_Phone_V1_LinkForPaymentRequest.with {
            $0.phoneNumber = .with { $0.value = phone }
            $0.auth = owner.authFor(message: $0)
        }

        Task { @MainActor in
            do {
                let response = try await service.linkForPayment(request, options: .unaryDefault)
                let error = ErrorLinkForPayment(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to link phone number for payment", metadata: ["error": "\(error)"])
                    completion(.failure(error))
                    return
                }
                logger.info("Phone number linked for payment successfully")
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

public enum ErrorSendVerificationCode: Int, Error, Equatable, Sendable {
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
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorCheckVerificationCode: Int, Error, Equatable, Sendable {
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
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorUnlinkPhone: Int, Error, Equatable, Sendable {
    case ok
    case denied
    case unknown = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorLinkForPayment: Int, Error, Equatable, Sendable {
    case ok
    case denied
    /// The phone number is not associated with the requesting user.
    case notAssociated
    case unknown = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorSendVerificationCode: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .rateLimited, .invalidPhoneNumber, .unsupportedPhoneType: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorCheckVerificationCode: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .rateLimited, .invalidCode, .noVerification: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorUnlinkPhone: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorLinkForPayment: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notAssociated: .info
        case .unknown, .rejected: .error
        }
    }
}
