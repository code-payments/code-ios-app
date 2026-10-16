//
//  CommunityService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.community-service")

final class CommunityService: Sendable {

    private let service: Flipcash_Community_V1_Community.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Community_V1_Community.Client(wrapping: client)
    }

    /// Fetches the community of the currency launched as `mint`.
    func getCommunity(mint: PublicKey, owner: KeyPair, completion: @Sendable @escaping (Result<Community, ErrorGetCommunity>) -> Void) {
        logger.info("Fetching community", metadata: ["mint": "\(mint.base58)"])

        let request = Flipcash_Community_V1_GetCommunityRequest.with {
            $0.mint = mint.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getCommunity(request, options: .unaryDefault)
                let result = Self.communityResult(response)
                if case .failure(let error) = result {
                    logger.error("Failed to fetch community", metadata: ["error": "\(error)"])
                }
                await MainActor.run { completion(result) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// The community a response carried, or the failure it reported.
    static func communityResult(_ response: Flipcash_Community_V1_GetCommunityResponse) -> Result<Community, ErrorGetCommunity> {
        let error = ErrorGetCommunity(rawValue: response.result.rawValue) ?? .unknown
        switch error {
        case .ok:
            guard response.hasCommunity, let community = try? Community(response.community) else {
                return .failure(.unknown)
            }
            return .success(community)
        case .notFound, .unknown, .transportFailure, .cancelled, .rejected:
            return .failure(error)
        }
    }
}

// MARK: - Errors -

public enum ErrorGetCommunity: Int, Error {
    case ok
    /// The mint is not a currency launched on Flipcash, or is not yet available.
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorGetCommunity: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}
