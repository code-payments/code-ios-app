//
//  Client+Transaction.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine

extension Client {
 
    public func createAccounts(with organizer: Organizer) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.createAccounts(with: organizer) { c.resume(with: $0) }
        }
    }
    
    public func transfer(amount: KinAmount, fee: Kin = 0, organizer: Organizer, rendezvous: PublicKey, destination: PublicKey, isWithdrawal: Bool) async throws {
        let intent = try await withCheckedThrowingContinuation { c in
            transactionService.transfer(
                amount: amount,
                fee: fee,
                organizer: organizer,
                rendezvous: rendezvous,
                destination: destination,
                isWithdrawal: isWithdrawal,
                completion: { c.resume(with: $0) }
            )
        }
        
        await MainActor.run {
            organizer.set(tray: intent.resultTray)
        }
    }
    
    public func receiveFromIncoming(amount: Kin, organizer: Organizer) async throws {
        let intent = try await withCheckedThrowingContinuation { c in
            transactionService.receiveFromIncoming(
                amount: amount,
                organizer: organizer,
                completion: { c.resume(with: $0) }
            )
        }
        
        await MainActor.run {
            organizer.set(tray: intent.resultTray)
        }
    }
    
    public func receiveFromPrimary(amount: Kin, organizer: Organizer) async throws  {
        let intent = try await withCheckedThrowingContinuation { c in
            transactionService.receiveFromPrimary(
                amount: amount,
                organizer: organizer,
                completion: { c.resume(with: $0) }
            )
        }
        
        await MainActor.run {
            organizer.set(tray: intent.resultTray)
        }
    }
    
    public func receiveFromRelationship(domain: Domain, amount: Kin, organizer: Organizer) async throws {
        let intent = try await withCheckedThrowingContinuation { c in
            transactionService.receiveFromRelationship(
                domain: domain,
                amount: amount,
                organizer: organizer,
                completion: { c.resume(with: $0) }
            )
        }
        
        await MainActor.run {
            organizer.set(tray: intent.resultTray)
        }
    }
    
    public func withdraw(amount: KinAmount, organizer: Organizer, destination: PublicKey) async throws {
        let intent = try await withCheckedThrowingContinuation { c in
            transactionService.withdraw(
                amount: amount,
                organizer: organizer,
                destination: destination,
                completion: { c.resume(with: $0) }
            )
        }
        
        await MainActor.run {
            organizer.set(tray: intent.resultTray)
        }
    }
    
    public func upgradePrivacy(mnemonic: MnemonicPhrase, upgradeableIntent: UpgradeableIntent) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.upgradePrivacy(mnemonic: mnemonic, upgradeableIntent: upgradeableIntent) { c.resume(with: $0) }
        }
    }
    
    // MARK: - Remote Send -
    
    public func sendRemotely(amount: KinAmount, organizer: Organizer, rendezvous: PublicKey, giftCard: GiftCardAccount) async throws {
        let intent = try await withCheckedThrowingContinuation { c in
            transactionService.sendRemotely(amount: amount, organizer: organizer, rendezvous: rendezvous, giftCard: giftCard) { c.resume(with: $0) }
        }
        
        await MainActor.run {
            organizer.set(tray: intent.resultTray)
        }
    }
    
    public func receiveRemotely(amount: Kin, organizer: Organizer, giftCard: GiftCardAccount, isVoiding: Bool) async throws {
        let intent = try await withCheckedThrowingContinuation { c in
            transactionService.receiveRemotely(amount: amount, organizer: organizer, giftCard: giftCard, isVoiding: isVoiding) { c.resume(with: $0) }
        }
        
        await MainActor.run {
            organizer.set(tray: intent.resultTray)
        }
    }
    
    // MARK: - Relationship -
    
    public func establishRelationship(organizer: Organizer, domain: Domain) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.establishRelationship(organizer: organizer, domain: domain) { c.resume(with: $0) }
        }
    }
    
    // MARK: - AirDrop -
    
    public func airdrop(type: AirdropType, owner: KeyPair) async throws -> PaymentMetadata {
        try await withCheckedThrowingContinuation { c in
            transactionService.airdrop(type: type, owner: owner) { c.resume(with: $0) }
        }
    }
    
    // MARK: - Migration -
    
    private func migrateToPrivacy(amount: Kin, organizer: Organizer) async throws  {
        let intent = try await withCheckedThrowingContinuation { c in
            transactionService.migrateToPrivacy(
                amount: amount,
                organizer: organizer,
                completion: { c.resume(with: $0) }
            )
        }
        
        await MainActor.run {
            organizer.set(tray: intent.resultTray)
        }
    }
    
    public func migrateToPrivacy(amountToMigrate: Kin, organizer: Organizer) async throws  {
        try await createAccounts(with: organizer)
        try await migrateToPrivacy(amount: amountToMigrate, organizer: organizer)
        
        // There's nothing to receive if we're
        // migrating an empty account
        if amountToMigrate > 0 {
            try await receiveFromPrimary(
                amount: amountToMigrate.truncating(),
                organizer: organizer
            )
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
    
    // MARK: - History -
    
    public func fetchPaymentHistory(owner: KeyPair, after id: ID? = nil, pageSize: Int) async throws -> [HistoricalTransaction] {
        try await withCheckedThrowingContinuation { c in
            transactionService.fetchPaymentHistory(owner: owner, after: id, pageSize: pageSize) { c.resume(with: $0) }
        }
    }
    
    // MARK: - Withdrawals -
    
    public func fetchDestinationMetadata(destination: PublicKey) async -> DestinationMetadata {
        await withCheckedContinuation { c in
            transactionService.fetchDestinationMetadata(destination: destination) { c.resume(with: $0) }
        }
    }
    
    // MARK: - Upgrade -
    
    public func fetchUpgradeableIntents(owner: KeyPair) async throws -> [UpgradeableIntent] {
        try await withCheckedThrowingContinuation { c in
            transactionService.fetchUpgradeableIntents(owner: owner) { c.resume(with: $0) }
        }
    }
}
