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
    
    var maxDeposit: Kin {
        limits?.maxDeposit ?? 0
    }
    
    private(set) var limits: Limits?
    
    private var lastSwap: Date?

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
        let limits = try await client.fetchTransactionLimits(
            owner: organizer.ownerKeyPair,
            since: .todayAtMidnight()
        )
        
        var metadata: [String: Any] = [:]
        if let sendLimit = limits.sendLimitFor(currency: .usd) {
            metadata["limitNextTx"] = sendLimit.nextTransaction
            metadata["isStale"] = limits.isStale ? true : false
        }
        
        ErrorReporting.breadcrumb(
            name: "[FLOW] Fetched limits",
            metadata: metadata,
            type: .process
        )
        
        self.limits = limits
    }
    
    // MARK: - Balance -
    
    func fetchBalance() async throws -> Kin {
        let infos = try await client.fetchAccountInfos(owner: organizer.ownerKeyPair)
        organizer.setAccountInfo(infos)
        
        ErrorReporting.breadcrumb(
            name: "[FLOW] Fetched account infos",
            metadata: [
                "tray": organizer.tray.reportableRepresentation(),
            ],
            type: .process
        )
        
        await swapIfNeeded()
        
        try await receiveFromIncoming()
        
        return organizer.availableBalance
    }
    
    // MARK: - Swaps -
    
    private func swapIfNeeded() async {
        // We need to check and see if the USDC account has a balance,
        // if so, we'll initiate a swap to Kin. The nuance here is that
        // the balance of the USDC account is reported as `Kin`, where the
        // quarks represent the lamport balance of the account.
        guard let info = organizer.info(for: .swap), info.balance.quarks > 0 else {
            return
        }
        
        let timeout: Int = 45 // seconds
        
        // Ensure that it's been at least `timeout` seconds since we try
        // another swap if one is already in-flight.
        if let existingSwap = lastSwap, existingSwap.secondsBetween(date: .now()) < timeout {
            return
        }
        
        lastSwap = .now()
        do {
            try await client.initiateSwap(organizer: organizer)
        } catch {
            ErrorReporting.captureError(error, reason: "USDC Swap Failed")
        }
    }
    
    // MARK: - Transfer -
    
    private func transferPreflight(amount: Kin) async throws {
        let neededKin = amount > organizer.slotsBalance ? amount - organizer.slotsBalance : 0
        
        // If the there's insufficient funds in the slots
        // we'll need to top them up from incoming, relationship
        // and primary accounts, in that order.
        if neededKin > 0 {
            
            // 1. Receive funds from incoming accounts as those
            // will rotate more frequently than other types of accounts
            let receivedKin = try await receiveFromIncoming()
            
            // 2. Pull funds from relationships if there's still funds
            // missing in buckets after the receiving from primary
            if receivedKin < neededKin {
                
                // This is a preflight check so we want to be efficient here. If
                // we don't need to receive all relationships, we just need to
                // ensure we have funds in slots for this transactions
                try await receiveFromRelationships(upTo: neededKin - receivedKin)
            }
            
            // 3. If the amount is still larger than what's available
            // in the slots, we'll need to move funds from primary
            // deposits into slots after receiving
            if amount > organizer.slotsBalance {
                try await receiveFromPrimaryIfWithinLimits()
            }
        }
    }
    
    func transfer(amount: KinAmount, fee: Kin, additionalFees: [Fee], rendezvous: PublicKey, destination: PublicKey, withdrawal: Bool = false, tipAccount: TipAccount? = nil) async throws {
        let truncatedAmount = amount.truncatingQuarks()
        
        try await transferPreflight(amount: truncatedAmount.kin)
        try await client.transfer(
            amount: truncatedAmount,
            fee: fee,
            additionalFees: additionalFees,
            organizer: organizer,
            rendezvous: rendezvous,
            destination: destination,
            isWithdrawal: withdrawal,
            tipAccount: tipAccount
        )
        
        ErrorReporting.breadcrumb(
            name: "[FLOW] Transferred",
            metadata: [
                "fee": fee.description,
                "rendezvous": rendezvous.base58,
                "tipAccount": tipAccount?.username ?? "nil"
            ],
            amount: truncatedAmount,
            type: .process
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
        
        ErrorReporting.breadcrumb(
            name: "[FLOW] Sent remotely",
            metadata: [
                "rendezvous": rendezvous.base58,
            ],
            amount: truncatedAmount,
            type: .process
        )
        
        return organizer.availableBalance
    }
    
    func receiveRemote(giftCard: GiftCardAccount) async throws -> (receivedAmount: KinAmount, balance: Kin) {
        
        // Before we can receive from the gift card account
        // we have to determine the balance of the account
        let infos = try? await client.fetchAccountInfos(owner: giftCard.cluster.authority.keyPair)
        
        guard let info = infos?.first?.value else {
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
        
        ErrorReporting.breadcrumb(
            name: "[FLOW] Receive remotely",
            amount: kinAmount,
            type: .process
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
        
        ErrorReporting.breadcrumb(
            name: "[FLOW] Refund gift card",
            kin: amount,
            type: .process
        )
        
        return try await fetchBalance()
    }
    
    // MARK: - AirDrop -
    
    func airdropFirstKin() async throws -> (metadata: PaymentMetadata, balance: Kin) {
        let metadata = try await client.airdrop(type: .getFirstKin, owner: organizer.ownerKeyPair)
        
        ErrorReporting.breadcrumb(
            name: "[FLOW] Airdrop complete",
            amount: metadata.amount,
            type: .process
        )
        
        let balance = try await fetchBalance()
        
        try await receiveFromPrimaryIfWithinLimits()
        
        return (metadata, balance)
    }
    
    // MARK: - Flow Withdraw -
    
    func withdrawExternally(amount: KinAmount, to destination: PublicKey) async throws {
        try validate(amount: amount)
        
        let intent = KeyPair.generate()!
        
        var steps: [String] = []
        steps.append("Attempting withdrawal...")

        do {
            
            let primaryBalance = organizer.availableDepositBalance.truncating()
            
            // If the primary account has less Kin than the amount
            // requested for withdrawal, we'll need to execute a
            // private transfer to the primary account before we
            // can make a public transfer to destination.
            if primaryBalance < amount.kin {
                
                var missingBalance = amount.kin - primaryBalance
                steps.append("Amount exceeds primary balance.")
                steps.append("Missing balance: \(missingBalance)")
                
                // 1. If we're missing funds, we'll pull funds
                // from relationship accounts first.
                if missingBalance > 0 {
                    let receivedFromRelationships = try await receiveFromRelationships(upTo: missingBalance)
                    missingBalance = missingBalance - receivedFromRelationships
                    
                    steps.append("Pulled from relationships: \(receivedFromRelationships)")
                    steps.append("Missing balance: \(missingBalance)")
                }
                
                // 2. If we still need funds to fulfill the withdrawal
                // it's likely that they are stuck in incoming and bucket
                // accounts. We'll need to pull those out into primary.
                if missingBalance > 0 {
                    
                    // 3. It's possible that there's funds still left in
                    // an incoming account. If we're still missing funds
                    // for withdrawal, we'll pull from incoming.
                    if availableIncomingAmount() > 0 {
                        let receivedFromIncoming = try await receiveFromIncoming()
                        
                        steps.append("Pulled from incoming: \(receivedFromIncoming)")
                        steps.append("Missing balance: \(missingBalance)")
                    }
                    
                    
                    // 4. In the event that it's a full withdrawal or if
                    // more funds are required, we'll need to do a private
                    // transfer from bucket accounts.
                    try await client.transfer(
                        amount: KinAmount(kin: missingBalance, rate: .oneToOne),
                        fee: 0,
                        additionalFees: [],
                        organizer: organizer,
                        rendezvous: intent.publicKey,
                        destination: organizer.primaryVault,
                        isWithdrawal: true,
                        tipAccount: nil
                    )
                    
                    steps.append("Pulled from buckets: \(missingBalance)")
                    
                    try await fetchLimits()
                }
                
                // 5. Update balances and limits after the withdrawal since
                // it's likely that this withdrawal affected both but at the
                // very least, we need updated balances for all accounts.
                _ = try await fetchBalance()
            }
            
            trace(.warning, components: steps)
            
            // 5. Execute withdrawal
            try await client.withdraw(
                amount: amount,
                organizer: organizer,
                destination: destination
            )
            
            ErrorReporting.breadcrumb(
                name: "[FLOW] Withdraw completed",
                amount: amount,
                type: .process
            )
            
            Analytics.withdrawal(amount: amount)
            
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
        if organizer.slotsBalance < maxDeposit {
            try await receiveFromRelationships(upTo: maxDeposit)
        }
        try await receiveFromPrimaryIfWithinLimits()
        try await receiveFromIncoming()
    }
    
    private func receiveFromPrimaryIfWithinLimits() async throws {
        let depositBalance = organizer.availableDepositBalance
        
        guard depositBalance.hasWholeKin else {
            // Nothing to deposit
            return
        }
        
        // We want to deposit the smaller of the two: balance in the
        // primary account or the max allowed amount provided by server
        let depositAmount = min(depositBalance, maxDeposit)
        
        if depositAmount.hasWholeKin {
            trace(.warning, components: "Receiving from primary: \(depositAmount)", "Max allowed deposit: \(maxDeposit)")
            
            try await client.receiveFromPrimary(
                amount: depositAmount.truncating(),
                organizer: organizer
            )
            
            ErrorReporting.breadcrumb(
                name: "[FLOW] Received from primary",
                kin: depositAmount.truncating(),
                type: .process
            )
            
            try await fetchLimits()
        }
    }
    
    func availableIncomingAmount() -> Kin {
        organizer.availableIncomingBalance.truncating()
    }
    
    @discardableResult
    private func receiveFromIncoming() async throws -> Kin {
        let incomingBalance = availableIncomingAmount()
        guard incomingBalance > 0 else {
            return 0
        }
        
        try await client.receiveFromIncoming(
            amount: incomingBalance,
            organizer: organizer
        )
        
        ErrorReporting.breadcrumb(
            name: "[FLOW] Received from incoming",
            kin: incomingBalance,
            type: .process
        )
        
        trace(.success, components: "Received from incoming: \(incomingBalance)")
        return incomingBalance
    }
    
    @discardableResult
    private func receiveFromRelationships(upTo limit: Kin? = nil) async throws -> Kin {
        var receivedTotal: Kin = 0
        
        for relationship in organizer.relationshipsLargestFirst() {
            guard relationship.partialBalance > 0 else {
                // Ignore empty relationship accounts
                continue
            }
            
            trace(.warning, components: "Receiving from relationships: \(relationship.partialBalance)")
            
            try await client.receiveFromRelationship(
                domain: relationship.domain,
                amount: relationship.partialBalance,
                organizer: organizer
            )
            
            ErrorReporting.breadcrumb(
                name: "[FLOW] Received from relationship",
                metadata: [
                    "domain": relationship.domain.relationshipHost,
                ],
                kin: relationship.partialBalance,
                type: .process
            )
            
            receivedTotal = receivedTotal + relationship.partialBalance
            
            // Bail early if a limit is set
            if let limit, receivedTotal >= limit {
                return receivedTotal
            }
        }
        
        return receivedTotal
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
