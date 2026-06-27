//
//  AccountInfoService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.account-info-service")

final class AccountInfoService: Sendable {

    private let service: Ocp_Account_V1_Account.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Ocp_Account_V1_Account.Client(wrapping: client)
    }

    func fetchAccountInfo(type: AccountInfoType, owner: KeyPair, requestingOwner: KeyPair?, completion: @Sendable @escaping (Result<AccountInfo, ErrorFetchBalance>) -> Void) {
        var request = Ocp_Account_V1_GetTokenAccountInfosRequest()
        request.owner = owner.publicKey.solanaAccountID
        if let requestingOwner {
            request.requestingOwner = requestingOwner.publicKey.solanaAccountID
        }

        // Compute BOTH signatures against the unsigned message, then assign.
        // Assigning the first signature before computing the second would
        // change the serialized bytes the second sign() sees, and the server
        // would reject the request.
        let ownerSignature: Ocp_Common_V1_Signature = request.sign(with: owner)
        let requestingSignature: Ocp_Common_V1_Signature? = requestingOwner.map { request.sign(with: $0) }

        request.signature = ownerSignature
        if let requestingSignature {
            request.requestingOwnerSignature = requestingSignature
        }

        Task {
            do {
                let response = try await service.getTokenAccountInfos(request, options: .unaryDefault)

                let error = ErrorFetchBalance(rawValue: response.result.rawValue) ?? .unknown
                if error == .ok {
                    switch Self.accountInfo(in: response, type: type) {
                    case .success(let account):
                        await MainActor.run { completion(.success(account)) }
                    case .failure(let failure):
                        logger.error("Account not in list of accounts returned", metadata: [
                            "expectedType": "\(type)",
                            "returnedCount": "\(response.tokenAccountInfos.count)",
                        ])
                        await MainActor.run { completion(.failure(failure)) }
                    }

                } else {
                    logger.error("Failed to fetch account info", metadata: ["owner": "\(owner.publicKey.base58)"])
                    await MainActor.run { completion(.failure(error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    static func accountInfo(in response: Ocp_Account_V1_GetTokenAccountInfosResponse, type: AccountInfoType) -> Result<AccountInfo, ErrorFetchBalance> {
        let matching = response.tokenAccountInfos.values.filter {
            $0.accountType == type.proto
        }

        guard !matching.isEmpty else {
            return .failure(.accountNotInList)
        }

        guard let account = matching.compactMap({ try? AccountInfo($0) }).first else {
            return .failure(.parseFailed)
        }

        return .success(account)
    }

    /// Fetches the user's plain SPL associated token account for a specific
    /// mint via `GetTokenAccountInfos` with a server-side mint filter. Returns
    /// `nil` when no ATA exists yet (e.g. the user has never received this
    /// mint), which sweep callers treat as a zero balance.
    func fetchAssociatedTokenAccount(
        owner: KeyPair,
        mint: PublicKey,
        completion: @Sendable @escaping (Result<AccountInfo?, ErrorFetchBalance>) -> Void
    ) {
        let request = Ocp_Account_V1_GetTokenAccountInfosRequest.with {
            $0.owner = owner.publicKey.solanaAccountID
            $0.filterByMintAddress = mint.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }

        Task {
            do {
                let response = try await service.getTokenAccountInfos(request, options: .unaryDefault)
                let error = ErrorFetchBalance(rawValue: response.result.rawValue) ?? .unknown
                switch error {
                case .ok:
                    let account = response.tokenAccountInfos.compactMap {
                        $0.value.accountType == .associatedTokenAccount ? (try? AccountInfo($0.value)) : nil
                    }.first
                    await MainActor.run { completion(.success(account)) }
                case .notFound:
                    // No ATA for this mint yet — caller treats as zero balance.
                    await MainActor.run { completion(.success(nil)) }
                case .unknown, .accountNotInList, .parseFailed, .transportFailure:
                    logger.error("Failed to fetch associated token account", metadata: [
                        "owner": "\(owner.publicKey.base58)",
                        "mint": "\(mint.base58)",
                    ])
                    await MainActor.run { completion(.failure(error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func fetchPrimaryAccounts(owner: KeyPair, completion: @Sendable @escaping (Result<[AccountInfo], ErrorFetchBalance>) -> Void) {
        let request = Ocp_Account_V1_GetTokenAccountInfosRequest.with {
            $0.owner = owner.publicKey.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }

        Task {
            do {
                let response = try await service.getTokenAccountInfos(request, options: .unaryDefault)
                let error = ErrorFetchBalance(rawValue: response.result.rawValue) ?? .unknown
                if error == .ok {
                    let accounts: [AccountInfo] = response.tokenAccountInfos.filter {
                        $0.value.accountType == .primary
                    }.compactMap {
                        (try? AccountInfo($0.value))
                    }

                    await MainActor.run { completion(.success(accounts)) }

                } else {
                    logger.error("Failed to fetch primary accounts", metadata: ["owner": "\(owner.publicKey.base58)"])
                    await MainActor.run { completion(.failure(error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

}

// MARK: - Types -

public enum AccountInfoType: Sendable {
    case primary
    case giftCard
    case pool

    fileprivate var proto: Ocp_Common_V1_AccountType {
        switch self {
        case .primary:  return .primary
        case .giftCard: return .remoteSendGiftCard
        case .pool:     return .pool
        }
    }
}

// MARK: - Errors -

public enum ErrorFetchBalance: Int, Error, Equatable, Sendable {
    case ok
    case notFound
    case unknown          = -1
    case accountNotInList = -2
    case parseFailed      = -3
    case transportFailure = -4
}

extension ErrorFetchBalance: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .notFound, .accountNotInList, .transportFailure: false
        case .unknown, .parseFailed: true
        }
    }
}
