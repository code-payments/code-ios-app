//
//  BalanceService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.balance-service")

final class BalanceService: Sendable {

    private let service: Ocp_Balance_V1_Balance.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Ocp_Balance_V1_Balance.Client(wrapping: client)
    }

    /// Fetches the core-mint balance for a single owner account. Unlike every
    /// other Payments API request, `GetBalancesRequest` carries no auth/signature
    /// field — the server allows reading balance for any owner, not just the
    /// caller's own, so this takes a bare `PublicKey` rather than a signing
    /// `KeyPair`.
    ///
    /// The underlying RPC is batched — `GetBalances` takes a list of owners and
    /// an optional mint filter, returning an owner → mint → value map — but
    /// nothing in the app currently needs more than one owner's balance at a
    /// time, so this wrapper stays single-owner-shaped and reads the one entry
    /// it asked for back out of the map.
    func getBalance(owner: PublicKey, completion: @Sendable @escaping (Result<TokenAmount, ErrorGetBalance>) -> Void) {
        logger.info("Fetching balance")

        let request = Ocp_Balance_V1_GetBalancesRequest.with {
            $0.owners = [owner.solanaAccountID]
        }

        Task {
            do {
                let response = try await service.getBalances(request, options: .unaryDefault)
                let error = ErrorGetBalance(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch balance", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                // An owner absent from the map simply has no balances — that's
                // zero, not an error. (The old response's NOT_FOUND result case
                // is gone; this replaces it.)
                let quarks = response.balancesByOwner[owner.base58]?.coreMintValue ?? 0
                let balance = TokenAmount(quarks: quarks, mint: .usdf)
                await MainActor.run { completion(.success(balance)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorGetBalance: Int, Error, Equatable, Sendable {
    case ok
    case denied
    case unknown          = -1
    case transportFailure = -2
    case cancelled        = -3
    case rejected         = -4
}

extension ErrorGetBalance: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied: .info
        case .unknown, .rejected: .error
        }
    }
}
