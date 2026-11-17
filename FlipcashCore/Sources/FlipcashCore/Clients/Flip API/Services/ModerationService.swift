//
//  ModerationService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.moderation-service")

final class ModerationService: Sendable {

    private let service: Flipcash_Moderation_V1_Moderation.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Moderation_V1_Moderation.Client(wrapping: client)
    }

    /// Builds the request with every field set before signing, so the
    /// signature covers `kind`.
    static func moderateTextRequest(_ text: String, kind: ModerationTextKind, owner: KeyPair) -> Flipcash_Moderation_V1_ModerateTextRequest {
        .with {
            $0.text = text
            $0.kind = kind.proto
            $0.auth = owner.authFor(message: $0)
        }
    }

    /// Builds the request with every field set before signing, so the
    /// signature covers `kind`.
    static func moderateImageRequest(_ imageData: Data, kind: ModerationImageKind, owner: KeyPair) -> Flipcash_Moderation_V1_ModerateImageRequest {
        .with {
            $0.imageData = imageData
            $0.kind = kind.proto
            $0.auth = owner.authFor(message: $0)
        }
    }

    func moderateText(
        _ text: String,
        kind: ModerationTextKind,
        owner: KeyPair,
        completion: @Sendable @escaping (Result<ModerationAttestation, ErrorModeration>) -> Void
    ) {
        logger.info("Moderating text", metadata: ["length": "\(text.count)", "kind": "\(kind)"])

        let request = Self.moderateTextRequest(text, kind: kind, owner: owner)

        Task {
            do {
                let response = try await service.moderateText(request, options: .unaryDefault)
                switch response.result {
                case .ok where response.isAllowed:
                    do {
                        let attestation = try ModerationAttestation(response.attestation)
                        logger.info("Text moderation passed")
                        await MainActor.run { completion(.success(attestation)) }
                    } catch {
                        logger.error("Failed to serialize moderation attestation", metadata: ["error": "\(error)"])
                        await MainActor.run { completion(.failure(.unknown)) }
                    }

                case .ok, .denied:
                    logger.info("Text moderation denied", metadata: ["category": "\(response.flaggedCategory)"])
                    await MainActor.run { completion(.failure(.denied(response.flaggedCategory))) }

                case .unsupportedLanguage:
                    logger.info("Text moderation reported unsupported language")
                    await MainActor.run { completion(.failure(.unsupportedLanguage)) }

                case .UNRECOGNIZED:
                    logger.error("Text moderation returned unrecognized result")
                    await MainActor.run { completion(.failure(.unknown)) }
                }
            } catch {
                logger.error("Text moderation gRPC error", metadata: ["error": "\(error)"])
                await MainActor.run { completion(.failure(.network(error))) }
            }
        }
    }

    func moderateImage(
        _ imageData: Data,
        kind: ModerationImageKind,
        owner: KeyPair,
        completion: @Sendable @escaping (Result<ModerationAttestation, ErrorModeration>) -> Void
    ) {
        logger.info("Moderating image", metadata: ["bytes": "\(imageData.count)", "kind": "\(kind)"])

        let request = Self.moderateImageRequest(imageData, kind: kind, owner: owner)

        Task {
            do {
                let response = try await service.moderateImage(request, options: .unaryDefault)
                switch response.result {
                case .ok where response.isAllowed:
                    do {
                        let attestation = try ModerationAttestation(response.attestation)
                        logger.info("Image moderation passed")
                        await MainActor.run { completion(.success(attestation)) }
                    } catch {
                        logger.error("Failed to serialize moderation attestation", metadata: ["error": "\(error)"])
                        await MainActor.run { completion(.failure(.unknown)) }
                    }

                case .ok, .denied:
                    logger.info("Image moderation denied", metadata: ["category": "\(response.flaggedCategory)"])
                    await MainActor.run { completion(.failure(.denied(response.flaggedCategory))) }

                case .unsupportedFormat:
                    logger.info("Image moderation unsupported format")
                    await MainActor.run { completion(.failure(.unsupportedFormat)) }

                case .UNRECOGNIZED:
                    logger.error("Image moderation returned unrecognized result")
                    await MainActor.run { completion(.failure(.unknown)) }
                }
            } catch {
                logger.error("Image moderation gRPC error", metadata: ["error": "\(error)"])
                await MainActor.run { completion(.failure(.network(error))) }
            }
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
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .denied, .unsupportedFormat, .unsupportedLanguage: .info
        case .unknown: .error
        case .network(let error): (error as? ServerError)?.reportingLevel ?? .error
        }
    }
}
