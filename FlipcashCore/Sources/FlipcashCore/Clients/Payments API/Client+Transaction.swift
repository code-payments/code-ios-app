//
//  Client+Transaction.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine

extension Client {
 
    public func createAccounts(owner: KeyPair, mint: PublicKey, cluster: AccountCluster, kind: AccountKind, derivationIndex: Int) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.createAccounts(owner: owner, mint: mint, cluster: cluster, kind: kind, derivationIndex: derivationIndex) { c.resume(with: $0) }
        }
    }
    
    public func transfer(exchangedFiat: ExchangedFiat, owner: AccountCluster, destination: PublicKey, rendezvous: PublicKey) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.transfer(
                exchangedFiat: exchangedFiat,
                sourceCluster: owner,
                destination: destination,
                owner: owner.authority.keyPair,
                rendezvous: rendezvous
            ) { c.resume(with: $0) }
        }
    }
    
    public func distributePoolWinnings(source: AccountCluster, distributions: [PoolDistribution], owner: KeyPair) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.distributePoolWinnings(
                source: source,
                distributions: distributions,
                owner: owner
            ) { c.resume(with: $0) }
        }
    }
    
    public func withdraw(exchangedFiat: ExchangedFiat, fee: Quarks, owner: AccountCluster, destinationMetadata: DestinationMetadata) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.withdraw(
                exchangedFiat: exchangedFiat,
                fee: fee,
                sourceCluster: owner,
                destinationMetadata: destinationMetadata,
                owner: owner.authority.keyPair
            ) { c.resume(with: $0) }
        }
    }
    
    public func sendCashLink(exchangedFiat: ExchangedFiat, ownerCluster: AccountCluster, giftCard: GiftCardCluster, rendezvous: PublicKey) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.sendCashLink(
                exchangedFiat: exchangedFiat,
                ownerCluster: ownerCluster,
                giftCard: giftCard,
                rendezvous: rendezvous
            ) { c.resume(with: $0) }
        }
    }
    
    public func receiveCashLink(usdc: Quarks, ownerCluster: AccountCluster, giftCard: GiftCardCluster) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.receiveCashLink(
                usdc: usdc,
                ownerCluster: ownerCluster,
                giftCard: giftCard
            ) { c.resume(with: $0) }
        }
    }
    
    public func voidCashLink(giftCardVault: PublicKey, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            transactionService.voidCashLink(giftCardVault: giftCardVault, owner: owner) { c.resume(with: $0) }
        }
    }
    
    // MARK: - AirDrop -
    
    @discardableResult
    public func airdrop(type: AirdropType, owner: KeyPair) async throws -> PaymentMetadata {
        try await withCheckedThrowingContinuation { c in
            transactionService.airdrop(type: type, owner: owner) { c.resume(with: $0) }
        }
    }
    
    // MARK: - Swaps -
    public func buy(amount: Quarks, of token: MintMetadata, sourceCluster: AccountCluster, owner: KeyPair,) async throws -> Void {
        try await withCheckedThrowingContinuation { c in
            transactionService.buy(amount: amount, of: token, sourceCluster: sourceCluster, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func sell(amount: Quarks, in token: MintMetadata, owner: KeyPair) async throws -> Void {
        try await withCheckedThrowingContinuation { c in
            transactionService.sell(amount: amount, in: token, owner: owner) { c.resume(with: $0) }
        }
    }
    
    // MARK: - Status -
    
    public func pollIntentMetadata(owner: KeyPair, intentID: PublicKey, maxAttempts: Int = 50) async throws -> IntentMetadata {
        for i in 0..<maxAttempts {
            do {
                let delay = 50 * (i / 10)
                if delay > 0 {
                    try await Task.delay(milliseconds: delay)
                }
                trace(.poll, components: "Delay: \(delay)ms", "Intent ID \(i): \(intentID.base58)")
                return try await fetchIntentMetadata(owner: owner, intentID: intentID)
            } catch {}
        }
        
        throw ClientError.pollLimitReached
    }
    
    func fetchIntentMetadata(owner: KeyPair, intentID: PublicKey) async throws -> IntentMetadata {
        try await withCheckedThrowingContinuation { c in
            transactionService.fetchIntentMetadata(owner: owner, intentID: intentID) { c.resume(with: $0) }
        }
    }
    
    // MARK: - Limits -
    
    public func fetchTransactionLimits(owner: KeyPair, since date: Date) async throws -> Limits {
        try await withCheckedThrowingContinuation { c in
            transactionService.fetchTransactionLimits(owner: owner, since: date) { c.resume(with: $0) }
        }
    }
    
    // MARK: - Withdrawals -
    
    public func fetchDestinationMetadata(destination: PublicKey, mint: PublicKey) async -> DestinationMetadata {
        await withCheckedContinuation { c in
            transactionService.fetchDestinationMetadata(destination: destination, mint: mint) { c.resume(with: $0) }
        }
    }
}

// MARK: - Error -

public enum ClientError: Error {
    case pollLimitReached
}
