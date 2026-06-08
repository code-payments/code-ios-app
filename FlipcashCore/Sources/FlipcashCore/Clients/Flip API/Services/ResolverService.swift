//
//  ResolverService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPC

private let logger = Logger(label: "flipcash.resolver-service")

final class ResolverService: CodeService<Flipcash_Resolver_V1_ResolverNIOClient> {

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

        let call = service.resolve(request)
        call.handle(on: queue, completion: completion) { response in
            switch response.result {
            case .ok:
                guard
                    case .address(let addressProto) = response.resolution.kind,
                    let publicKey = try? PublicKey(addressProto.value)
                else {
                    logger.error("Resolve OK but resolution missing address")
                    return .failure(.unknown)
                }
                return .success(publicKey)
            case .notFound:
                return .failure(.notFound)
            case .denied:
                logger.warning("Resolve denied")
                return .failure(.denied)
            case .UNRECOGNIZED(let raw):
                logger.warning("Resolve unknown result", metadata: ["raw": "\(raw)"])
                return .failure(.unknown)
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

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Resolver_V1_ResolverClientInterceptorFactoryProtocol {
    func makeResolveInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Resolver_V1_ResolveRequest, Flipcash_Resolver_V1_ResolveResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Resolver_V1_ResolverNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
