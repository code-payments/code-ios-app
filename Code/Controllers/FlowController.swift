//
//  FlowController.swift
//  Code
//
//  Created by Dima Bart on 2023-03-08.
//

import Foundation
import CodeServices

@MainActor
class FlowController: ObservableObject {
    
    var areLimitsStale: Bool {
        limits == nil || limits?.isStale == true
    }
    
    private(set) var limits: Limits?

    private let client: Client
    private let organizer: Organizer
    
    // MARK: - Init -
    
    init(client: Client, organizer: Organizer) {
        self.client = client
        self.organizer = organizer
    }
    
    // MARK: - Limits -
    
    func updateLimits() {
        Task {
            try await fetchLimits()
        }
    }
    
    private func fetchLimits() async throws {
        limits = try await client.fetchTransactionLimits(
            owner: organizer.ownerKeyPair,
            since: .todayAtMidnight()
        )
    }
    
    // MARK: - Balance -
    
    func fetchBalance() async throws -> Kin {
        let infos = try await client.fetchAccountInfos(owner: organizer.ownerKeyPair)
        organizer.setAccountInfo(infos)
        
        try await receiveFromIncomingIfRotationRequired()
        
        return organizer.availableBalance
    }
    
    // MARK: - Transfer -
    
    private func transferPreflight(amount: Kin) async throws {
        // We only need to receive funds if the amount is
        // not fully available from slots balances
        
        if amount > organizer.slotsBalance {
            
            // 1. Receive funds from incoming accounts before
            // we reach into primary / deposits
            try await receiveFromIncoming()
            
            // 2. If the amount is still larger than what's available
            // in the slots, we'll need to move funds from primary
            // deposits into slots after receiving
            if amount > organizer.slotsBalance {
                try await receiveFromPrimaryIfWithinLimits()
            }
        }
    }
    
    func transfer(amount: KinAmount, fee: Kin = 0, rendezvous: PublicKey, destination: PublicKey, withdrawal: Bool = false) async throws {
        let truncatedAmount = amount.truncatingQuarks()
        
        try await transferPreflight(amount: truncatedAmount.kin)
        try await client.transfer(
            amount: truncatedAmount,
            fee: fee,
            organizer: organizer,
            rendezvous: rendezvous,
            destination: destination,
            isWithdrawal: withdrawal
        )
    }
    
    // MARK: - Flow Remote Send -
    
    func sendRemotely(amount: KinAmount, rendezvous: PublicKey, giftCard: GiftCardAccount) async throws -> Kin {
        let truncatedAmount = amount.truncatingQuarks()

        try await transferPreflight(amount: truncatedAmount.kin)
        try await client.sendRemotely(
            amount: truncatedAmount,
            organizer: organizer,
            rendezvous: rendezvous,
            giftCard: giftCard
        )
        
        return organizer.availableBalance
    }
    
    func receiveRemote(giftCard: GiftCardAccount) async throws -> (receivedAmount: KinAmount, balance: Kin) {
        
        // Before we can receive from the gift card account
        // we have to determine the balance of the account
        let infos = try await client.fetchAccountInfos(owner: giftCard.cluster.authority.keyPair)
        
        guard let info = infos.first?.value else {
            throw Error.failedToFetchGiftCardInfo
        }
        
        guard let kinAmount = info.originalKinAmount else {
            throw Error.giftCardBalanaceNotFound
        }
        
        guard info.claimState != .claimed else {
            throw Error.giftCardClaimed
        }
        
        guard info.claimState != .claimed, info.claimState != .unknown else {
            throw Error.giftCardExpired
        }
        
        try await client.receiveRemotely(
            amount: info.balance,
            organizer: organizer,
            giftCard: giftCard,
            isVoiding: false
        )
        
        let balance = try await fetchBalance()
        
        return (kinAmount, balance)
    }
    
    func cancelRemoteSend(giftCard: GiftCardAccount, amount: Kin) async throws -> Kin {
        try await client.receiveRemotely(
            amount: amount,
            organizer: organizer,
            giftCard: giftCard,
            isVoiding: true
        )
        
        return try await fetchBalance()
    }
    
    // MARK: - AirDrop -
    
    func airdropFirstKin() async throws -> (metadata: PaymentMetadata, balance: Kin) {
        let metadata = try await client.airdrop(type: .getFirstKin, owner: organizer.ownerKeyPair)
        let balance  = try await fetchBalance()
        
        try await receiveFromPrimaryIfWithinLimits()
        
        return (metadata, balance)
    }
    
    // MARK: - Flow Withdraw -
    
    func withdrawExternally(amount: KinAmount, to destination: PublicKey) async throws {
        try validate(amount: amount)
        
        let intent = KeyPair.generate()!

        do {
            
            let primaryBalance = organizer.availableDepositBalance.truncating()
            
            // If the primary account has less Kin than the amount
            // requested for withdrawal, we'll need to execute a
            // private transfer to the primary account before we
            // can make a public transfer to destination
            if primaryBalance < amount.kin {
                
                let missingBalance = amount.kin - primaryBalance
                
                // It's possible that there's funds still left in
                // an incoming account. If the amount requested for
                // withdrawal is greater than primary + buckets, we
                // have to receive from incoming first
                if missingBalance > organizer.slotsBalance {
                    try await client.receiveFromIncoming(
                        amount: organizer.availableIncomingBalance.truncating(),
                        organizer: organizer
                    )
                }
                
                // Move funds into primary from buckets
                try await client.transfer(
                    amount: KinAmount(kin: missingBalance, rate: .oneToOne),
                    organizer: organizer,
                    rendezvous: intent.publicKey,
                    destination: organizer.primaryVault,
                    isWithdrawal: true
                )
                
                _ = try await fetchBalance()
            }
            
            try await client.withdraw(
                amount: amount,
                organizer: organizer,
                destination: destination
            )
            
        } catch {
            ErrorReporting.capturePayment(
                error: error,
                rendezvous: intent.publicKey,
                tray: organizer.tray,
                amount: amount,
                reason: "Withdrawal failed"
            )
            
            throw error
        }
    }
    
    // MARK: - Receives -
    
    func receiveIfNeeded() async throws {
        try await receiveFromPrimaryIfWithinLimits()
        try await receiveFromIncomingIfRotationRequired()
    }
    
    private func receiveFromPrimaryIfWithinLimits() async throws {
        let depositBalance = organizer.availableDepositBalance
        
        guard depositBalance.hasWholeKin else {
            // Nothing to deposit
            return
        }
        
        // We want to deposit the smaller of the two: balance in the
        // primary account or the max allowed amount provided by server
        let depositAmount = min(depositBalance, (limits?.maxDeposit ?? 0))
        
        if depositAmount.hasWholeKin {
            trace(.warning, components: "Receiving from primary: \(depositAmount)", "Max allowed deposit: \(limits?.maxDeposit.description ?? "nil")")
            
            try await client.receiveFromPrimary(
                amount: depositAmount.truncating(),
                organizer: organizer
            )
            
            try await fetchLimits()
        }
    }
    
    private func receiveFromIncomingIfRotationRequired() async throws {
        // Server will set this to `true` if the account
        // has more than 1 transaction + other heuristics
        if organizer.shouldRotateIncoming {
            try await receiveFromIncoming()
        }
    }
    
    private func receiveFromIncoming() async throws {
        let incomingBalance = organizer.availableIncomingBalance.truncating()
        guard incomingBalance > 0 else {
            return
        }
        
        trace(.warning, components: "Receiving from incoming: \(incomingBalance)")
        
        try await client.receiveFromIncoming(
            amount: incomingBalance,
            organizer: organizer
        )
    }
    
    // MARK: - Validation -
    
    private func validate(amount: KinAmount) throws {
        guard amount.kin.fractionalQuarks == 0 else {
            throw Error.invalidFractionalKinAmount
        }
        
        guard amount.kin <= organizer.availableBalance else {
            throw Error.insufficientFunds
        }
    }
}

extension FlowController {
    enum Error: Swift.Error {
        case invalidFractionalKinAmount
        case insufficientFunds
        case failedToFetchGiftCardInfo
        case giftCardBalanaceNotFound
        case giftCardClaimed
        case giftCardExpired
    }
}

extension FlowController {
    static let mock = FlowController(client: .mock, organizer: .mock)
}
