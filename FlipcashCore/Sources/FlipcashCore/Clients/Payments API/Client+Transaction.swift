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
 
    public func createAccounts(with owner: AccountCluster) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.createAccounts(with: owner) { c.resume(with: $0) }
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
    
    public func sendCashLink(exchangedFiat: ExchangedFiat, sourceCluster: AccountCluster, giftCard: GiftCardCluster, owner: KeyPair, rendezvous: PublicKey) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.sendCashLink(
                exchangedFiat: exchangedFiat,
                sourceCluster: sourceCluster,
                giftCard: giftCard,
                owner: owner,
                rendezvous: rendezvous
            ) { c.resume(with: $0) }
        }
    }
    
//    public func withdraw(amount: KinAmount, organizer: Organizer, destination: PublicKey) async throws {
//        let intent = try await withCheckedThrowingContinuation { c in
//            transactionService.withdraw(
//                amount: amount,
//                organizer: organizer,
//                destination: destination,
//                completion: { c.resume(with: $0) }
//            )
//        }
//        
//        await MainActor.run {
//            trace(.warning, components: "Updating tray from withdraw.")
//            organizer.set(tray: intent.resultTray)
//        }
//    }
//    
//    // MARK: - Remote Send -
//    
//    public func sendRemotely(amount: KinAmount, organizer: Organizer, rendezvous: PublicKey, giftCard: GiftCardAccount) async throws {
//        let intent = try await withCheckedThrowingContinuation { c in
//            transactionService.sendRemotely(amount: amount, organizer: organizer, rendezvous: rendezvous, giftCard: giftCard) { c.resume(with: $0) }
//        }
//        
//        await MainActor.run {
//            organizer.set(tray: intent.resultTray)
//        }
//    }
//    
//    public func receiveRemotely(amount: Kin, organizer: Organizer, giftCard: GiftCardAccount, isVoiding: Bool) async throws {
//        let intent = try await withCheckedThrowingContinuation { c in
//            transactionService.receiveRemotely(amount: amount, organizer: organizer, giftCard: giftCard, isVoiding: isVoiding) { c.resume(with: $0) }
//        }
//        
//        await MainActor.run {
//            organizer.set(tray: intent.resultTray)
//        }
//    }
//    
//    // MARK: - AirDrop -
    
    public func airdrop(type: AirdropType, owner: KeyPair) async throws -> PaymentMetadata {
        try await withCheckedThrowingContinuation { c in
            transactionService.airdrop(type: type, owner: owner) { c.resume(with: $0) }
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
    
//    // MARK: - Limits -
//    
//    public func fetchTransactionLimits(owner: KeyPair, since date: Date) async throws -> Limits {
//        try await withCheckedThrowingContinuation { c in
//            transactionService.fetchTransactionLimits(owner: owner, since: date) { c.resume(with: $0) }
//        }
//    }
//    
//    // MARK: - Withdrawals -
//    
//    public func fetchDestinationMetadata(destination: PublicKey) async -> DestinationMetadata {
//        await withCheckedContinuation { c in
//            transactionService.fetchDestinationMetadata(destination: destination) { c.resume(with: $0) }
//        }
//    }
}

// MARK: - Error -

public enum ClientError: Error {
    case pollLimitReached
}
