//
//  ModerationService.swift
//  FlipcashCore
//

import Foundation
import FlipcashCoreAPI
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

            case .UNRECOGNIZED:
                logger.error("Text moderation returned unrecognized result")
                completion(.failure(.unknown))
            }
        } failure: { error in
#if DEBUG
            if let attestation = bypassIfUnimplemented(error, rpc: "moderateText") {
                completion(.success(attestation))
                return
            }
#endif
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
#if DEBUG
            if let attestation = bypassIfUnimplemented(error, rpc: "moderateImage") {
                completion(.success(attestation))
                return
            }
#endif
            logger.error("Image moderation gRPC error", metadata: ["error": "\(error)"])
            completion(.failure(.network(error)))
        }
    }
}

#if DEBUG
// TEMPORARY BYPASS — remove once `flipcash.moderation.v1.Moderation` is deployed.
//
// Detects gRPC status code `unimplemented (12)` — which is what the server
// returns when the Moderation service is not yet registered — and substitutes
// a placeholder attestation so the wizard can progress during local testing.
// Release builds never hit this branch.
private func bypassIfUnimplemented(_ error: Error, rpc: String) -> ModerationAttestation? {
    guard let status = error as? GRPCStatus, status.code == .unimplemented else { return nil }
    logger.warning("Moderation RPC not yet implemented on backend — emitting placeholder attestation", metadata: [
        "rpc": "\(rpc)",
        "note": "DEBUG bypass; remove when server deploys the service",
    ])
    return ModerationAttestation(rawValue: Data([0x00]))
}
#endif

// MARK: - Errors -

public enum ErrorModeration: Error, Sendable {
    case denied(Flipcash_Moderation_V1_FlaggedCategory)
    case unsupportedFormat
    case unknown
    case network(Error)
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Moderation_V1_ModerationClientInterceptorFactoryProtocol {
    func makeModerateTextInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Moderation_V1_ModerateTextRequest, FlipcashCoreAPI.Flipcash_Moderation_V1_ModerateTextResponse>] {
        makeInterceptors()
    }

    func makeModerateImageInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Moderation_V1_ModerateImageRequest, FlipcashCoreAPI.Flipcash_Moderation_V1_ModerateImageResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Moderation_V1_ModerationNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
