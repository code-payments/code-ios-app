//
//  ModerationService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPC
import NIO

private let logger = Logger(label: "flipcash.moderation-service")

class ModerationService: CodeService<Flipcash_Moderation_V1_ModerationNIOClient>, @unchecked Sendable {

    func moderateText(
        _ text: String,
        auth: Flipcash_Common_V1_Auth,
        completion: @Sendable @escaping (Result<ModerationAttestation, ErrorModeration>) -> Void
    ) {
        logger.info("Moderating text", metadata: ["length": "\(text.count)"])

        var request = Flipcash_Moderation_V1_ModerateTextRequest()
        request.text = text
        request.auth = auth

        let call = service.moderateText(request)
        call.handle(on: queue) { response in
            switch response.result {
            case .ok where response.isAllowed:
                do {
                    let attestation = try ModerationAttestation(response.attestation)
                    logger.info("Text moderation passed")
                    completion(.success(attestation))
                } catch {
                    logger.error("Failed to serialize moderation attestation", metadata: ["error": "\(error)"])
                    completion(.failure(.unknown))
                }

            case .ok, .denied:
                logger.info("Text moderation denied", metadata: ["category": "\(response.flaggedCategory)"])
                completion(.failure(.denied(response.flaggedCategory)))

            case .unsupportedLanguage:
                logger.info("Text moderation reported unsupported language")
                completion(.failure(.unsupportedLanguage))

            case .UNRECOGNIZED:
                logger.error("Text moderation returned unrecognized result")
                completion(.failure(.unknown))
            }
        } failure: { error in
            logger.error("Text moderation gRPC error", metadata: ["error": "\(error)"])
            completion(.failure(.network(error)))
        }
    }

    func moderateImage(
        _ imageData: Data,
        auth: Flipcash_Common_V1_Auth,
        completion: @Sendable @escaping (Result<ModerationAttestation, ErrorModeration>) -> Void
    ) {
        logger.info("Moderating image", metadata: ["bytes": "\(imageData.count)"])

        var request = Flipcash_Moderation_V1_ModerateImageRequest()
        request.imageData = imageData
        request.auth = auth

        let call = service.moderateImage(request)
        call.handle(on: queue) { response in
            switch response.result {
            case .ok where response.isAllowed:
                do {
                    let attestation = try ModerationAttestation(response.attestation)
                    logger.info("Image moderation passed")
                    completion(.success(attestation))
                } catch {
                    logger.error("Failed to serialize moderation attestation", metadata: ["error": "\(error)"])
                    completion(.failure(.unknown))
                }

            case .ok, .denied:
                logger.info("Image moderation denied", metadata: ["category": "\(response.flaggedCategory)"])
                completion(.failure(.denied(response.flaggedCategory)))

            case .unsupportedFormat:
                logger.info("Image moderation unsupported format")
                completion(.failure(.unsupportedFormat))

            case .UNRECOGNIZED:
                logger.error("Image moderation returned unrecognized result")
                completion(.failure(.unknown))
            }
        } failure: { error in
            logger.error("Image moderation gRPC error", metadata: ["error": "\(error)"])
            completion(.failure(.network(error)))
        }
    }
}

// MARK: - Errors -

public enum ErrorModeration: Error, Sendable {
    case denied(Flipcash_Moderation_V1_FlaggedCategory)
    case unsupportedFormat
    case unsupportedLanguage
    case unknown
    case network(Error)
}

extension ErrorModeration: ServerError {
    public var isReportable: Bool {
        switch self {
        case .denied, .unsupportedFormat, .unsupportedLanguage: false
        case .unknown, .network: true
        }
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Moderation_V1_ModerationClientInterceptorFactoryProtocol {
    func makeModerateTextInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Moderation_V1_ModerateTextRequest, Flipcash_Moderation_V1_ModerateTextResponse>] {
        makeInterceptors()
    }

    func makeModerateImageInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Moderation_V1_ModerateImageRequest, Flipcash_Moderation_V1_ModerateImageResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Moderation_V1_ModerationNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
