//
//  BlocklistService.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.blocklist-service")

// MARK: - Public types -

/// One blocked user as returned by the server: identity + when they were blocked.
public struct BlockedUserEntry: Sendable {
    public let userID: UserID
    public let blockedAt: Date
}

/// A single page of blocked users from the server, with the cursor for the next page.
public struct BlocklistPage: Sendable {
    public let blockedUsers: [BlockedUserEntry]
    public let pagingToken: Data
    public let hasMore: Bool
}

// MARK: -

final class BlocklistService: Sendable {

    private let service: Flipcash_Blocklist_V1_Blocklist.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Blocklist_V1_Blocklist.Client(wrapping: client)
    }

    func blockUser(userID: UserID, owner: KeyPair, completion: @Sendable @escaping (Result<Void, ErrorBlocklist>) -> Void) {
        logger.info("Blocking user", metadata: ["userId": "\(userID)"])
        let request = Flipcash_Blocklist_V1_BlockUserRequest.with {
            $0.userID = userID.proto
            $0.auth = owner.authFor(message: $0)
        }
        Task {
            do {
                let response = try await service.blockUser(request, options: .unaryDefault)
                let error = ErrorBlocklist(rawValue: response.result.rawValue) ?? .unknown
                await MainActor.run { completion(error == .ok ? .success(()) : .failure(error)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func unblockUser(userID: UserID, owner: KeyPair, completion: @Sendable @escaping (Result<Void, ErrorBlocklist>) -> Void) {
        logger.info("Unblocking user", metadata: ["userId": "\(userID)"])
        let request = Flipcash_Blocklist_V1_UnblockUserRequest.with {
            $0.userID = userID.proto
            $0.auth = owner.authFor(message: $0)
        }
        Task {
            do {
                let response = try await service.unblockUser(request, options: .unaryDefault)
                let error = ErrorBlocklist(rawValue: response.result.rawValue) ?? .unknown
                await MainActor.run { completion(error == .ok ? .success(()) : .failure(error)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func getBlocklist(owner: KeyPair, pageSize: Int = 50, pagingToken: Data?, completion: @Sendable @escaping (Result<BlocklistPage, ErrorBlocklist>) -> Void) {
        let request = Flipcash_Blocklist_V1_GetBlocklistRequest.with {
            $0.queryOptions = .with {
                $0.pageSize = Int32(pageSize)
                if let pagingToken {
                    $0.pagingToken = .with { $0.value = pagingToken }
                }
            }
            $0.auth = owner.authFor(message: $0)
        }
        Task {
            do {
                let response = try await service.getBlocklist(request, options: .unaryDefault)
                let error = ErrorBlocklist(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                let users: [BlockedUserEntry] = response.blockedUsers.compactMap { proto in
                    guard let userID = try? UUID(data: proto.userID.value) else { return nil }
                    return BlockedUserEntry(userID: userID, blockedAt: proto.blockedAt.date)
                }
                let page = BlocklistPage(
                    blockedUsers: users,
                    pagingToken: response.pagingToken.value,
                    hasMore: response.hasMore_p
                )
                await MainActor.run { completion(.success(page)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

/// One error type covers all four blocklist RPCs: their result enums are subsets
/// of these cases (`BlockUser` uses `.denied`/`.userNotFound`/`.cannotBlockSelf`;
/// the others only `.denied`). The raw values line up with every response's
/// `Result` (ok=0, denied=1, userNotFound=2, cannotBlockSelf=3).
public enum ErrorBlocklist: Int, Error {
    case ok
    case denied
    case userNotFound
    case cannotBlockSelf
    case unknown          = -1
    case transportFailure = -2
    case cancelled        = -3
    case rejected         = -4
}

extension ErrorBlocklist: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .userNotFound, .cannotBlockSelf: .info
        case .unknown, .rejected: .error
        }
    }
}
