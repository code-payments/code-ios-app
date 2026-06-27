//
//  ResolverService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.resolver-service")

final class ResolverService: Sendable {

    private let service: Flipcash_Resolver_V1_Resolver.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Resolver_V1_Resolver.Client(wrapping: client)
    }

    /// Resolve an E.164 phone to the on-chain payment destination.
    /// Throws `.notFound` when the recipient is not on Flipcash; throws for
    /// hard failures (DENIED, network errors).
    func resolvePhone(
        _ e164: String,
        owner: KeyPair,
        completion: @Sendable @escaping (Result<PublicKey, ErrorResolve>) -> Void
    ) {
        logger.info("Resolving phone to payment destination")

        let request = Flipcash_Resolver_V1_ResolveRequest.with {
            $0.identifier = .with {
                $0.phone = .with { $0.value = e164 }
            }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.resolve(request, options: .unaryDefault)
                switch response.result {
                case .ok:
                    guard
                        case .address(let addressProto) = response.resolution.kind,
                        let publicKey = try? PublicKey(addressProto.value)
                    else {
                        logger.error("Resolve OK but resolution missing address")
                        await MainActor.run { completion(.failure(.unknown)) }
                        return
                    }
                    await MainActor.run { completion(.success(publicKey)) }
                case .notFound:
                    await MainActor.run { completion(.failure(.notFound)) }
                case .denied:
                    logger.warning("Resolve denied")
                    await MainActor.run { completion(.failure(.denied)) }
                case .UNRECOGNIZED(let raw):
                    logger.warning("Resolve unknown result", metadata: ["raw": "\(raw)"])
                    await MainActor.run { completion(.failure(.unknown)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorResolve: Int, Error, Equatable, Sendable {
    case ok = 0
    case denied = 1
    case notFound = 2
    case transportFailure = -2
    case unknown = -1
}

extension ErrorResolve: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .notFound, .transportFailure: false
        case .unknown: true
        }
    }
}
