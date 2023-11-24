//
//  Tray.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Tray: Equatable, Codable, Hashable {
    
    var slotsBalance: Kin {
        slots.reduce(into: 0) { $0 = $0 + $1.partialBalance }
    }
    
    var availableBalance: Kin {
        slotsBalance + availableDepositBalance + availableIncomingBalance
    }
    
    var availableDepositBalance: Kin {
        owner.partialBalance
    }
    
    var availableIncomingBalance: Kin {
        incoming.partialBalance
    }
    
    private(set) var slots : [Slot]
    
    private(set) var owner:    PartialAccount
    private(set) var incoming: PartialAccount
    private(set) var outgoing: PartialAccount
    
    private let mnemonic: MnemonicPhrase
    
    // MARK: - Init -
    
    init(mnemonic: MnemonicPhrase) {
        self.mnemonic = mnemonic
        self.owner = PartialAccount(
            cluster: AccountCluster(
                authority: .derive(using: .solana, mnemonic: mnemonic)
            )
        )
        
        self.slots = [
            Slot(type: .bucket1,    mnemonic: mnemonic),
            Slot(type: .bucket10,   mnemonic: mnemonic),
            Slot(type: .bucket100,  mnemonic: mnemonic),
            Slot(type: .bucket1k,   mnemonic: mnemonic),
            Slot(type: .bucket10k,  mnemonic: mnemonic),
            Slot(type: .bucket100k, mnemonic: mnemonic),
            Slot(type: .bucket1m,   mnemonic: mnemonic),
        ]
        
        self.incoming = PartialAccount(cluster: .incoming(for: 0, mnemonic: mnemonic))
        self.outgoing = PartialAccount(cluster: .outgoing(for: 0, mnemonic: mnemonic))
    }
    
    // MARK: - Temp Accounts -
    
    mutating func incrementIncoming() {
        setIndex(incoming.cluster.index + 1, for: .incoming)
    }
    
    mutating func incrementOutgoing() {
        setIndex(outgoing.cluster.index + 1, for: .outgoing)
    }
    
    mutating func setIndex(_ index: Int, for accountType: AccountType) {
        switch accountType {
        case .incoming:
            incoming = PartialAccount(cluster: .incoming(for: index, mnemonic: mnemonic))
        case .outgoing:
            outgoing = PartialAccount(cluster: .outgoing(for: index, mnemonic: mnemonic))
        case .primary, .bucket, .remoteSend, .relationship:
            fatalError("Unsupported.")
        }
    }
    
    // MARK: - Accounts -
    
    func allAccounts() -> [(type: AccountType, cluster: AccountCluster)] {
        [
            (.primary,  owner.cluster),
            (.incoming, incoming.cluster),
            (.outgoing, outgoing.cluster),
        ] + slots.map {
            (.bucket($0.type), $0.cluster)
        }
    }
    
    func cluster(for accountType: AccountType) -> AccountCluster {
        switch accountType {
        case .primary:
            return owner.cluster
            
        case .incoming:
            return incoming.cluster
            
        case .outgoing:
            return outgoing.cluster
            
        case .bucket(let slotType):
            return slot(for: slotType).cluster
            
        case .remoteSend:
            fatalError("Remote send account unsupported")
            
        case .relationship:
            fatalError("Relationship account unsupported")
        }
    }
    
    // MARK: - Slots -
    
    func slot(for type: SlotType) -> Slot {
        slots.first { $0.type == type }!
    }
    
    func slotDown(from type: SlotType) -> Slot? {
        let index = slots.firstIndex { $0.type == type }
        if let index = index, index > 0 {
            return slots[index - 1]
        }
        return nil
    }
    
    func slotUp(from type: SlotType) -> Slot? {
        let index = slots.firstIndex { $0.type == type }
        if let index = index, index < slots.count - 1 {
            return slots[index + 1]
        }
        return nil
    }
    
    // MARK: - Balances -
    
    mutating func increment(_ type: AccountType, kin: Kin) {
        switch type {
        case .primary:
            owner.partialBalance = owner.partialBalance + kin
        case .incoming:
            incoming.partialBalance = incoming.partialBalance + kin
        case .outgoing:
            outgoing.partialBalance = outgoing.partialBalance + kin
        case .bucket(let slotType):
            slots[slotType.rawValue].partialBalance = slots[slotType.rawValue].partialBalance + kin
        case .remoteSend:
            fatalError("Remote send account unsupported")
        case .relationship:
            fatalError("Relationship account unsupported")
        }
    }
    
    mutating func decrement(_ type: AccountType, kin: Kin) {
        switch type {
        case .primary:
            owner.partialBalance = owner.partialBalance - kin
        case .incoming:
            incoming.partialBalance = incoming.partialBalance - kin
        case .outgoing:
            outgoing.partialBalance = outgoing.partialBalance - kin
        case .bucket(let slotType):
            slots[slotType.rawValue].partialBalance = slots[slotType.rawValue].partialBalance - kin
        case .remoteSend:
            fatalError("Remote send account unsupported")
        case .relationship:
            fatalError("Relationship account unsupported")
        }
    }
    
    mutating func setBalances(_ balances: [AccountType: Kin]) {
        owner.partialBalance    = balances[.primary] ?? owner.partialBalance
        incoming.partialBalance = balances[.incoming] ?? incoming.partialBalance
        outgoing.partialBalance = balances[.outgoing] ?? outgoing.partialBalance
        
        slots[0].partialBalance = balances[.bucket(.bucket1)]    ?? slots[0].partialBalance
        slots[1].partialBalance = balances[.bucket(.bucket10)]   ?? slots[1].partialBalance
        slots[2].partialBalance = balances[.bucket(.bucket100)]  ?? slots[2].partialBalance
        slots[3].partialBalance = balances[.bucket(.bucket1k)]   ?? slots[3].partialBalance
        slots[4].partialBalance = balances[.bucket(.bucket10k)]  ?? slots[4].partialBalance
        slots[5].partialBalance = balances[.bucket(.bucket100k)] ?? slots[5].partialBalance
        slots[6].partialBalance = balances[.bucket(.bucket1m)]   ?? slots[6].partialBalance
    }
    
    func partialBalance(for type: AccountType) -> Kin {
        switch type {
        case .primary:
            return owner.partialBalance
            
        case .incoming:
            return incoming.partialBalance
            
        case .outgoing:
            return outgoing.partialBalance
            
        case .bucket(let slotType):
            return slot(for: slotType).partialBalance
            
        case .remoteSend:
            fatalError("Remote send account unsupported")
            
        case .relationship:
            fatalError("Relationship account unsupported")
        }
    }
    
    // MARK: - Redistribute -
    
    ///  Redistribute the bills in the organizer to ensure there are no gaps
    ///  in consecutive slots.
    ///
    ///  For example, avoid this:
    ///  ----------------------------------------------------------------
    ///  | slot 0 | slot 1 | slot 2 | slot 3 | slot 4 | slot 5 | slot 6 |
    ///  ----------------------------------------------------------------
    ///  |  1     |   0    |   10    |   10  |   0    |   0    |   0    | = 1,101
    ///     ^---------^--- not optimal
    ///
    ///  Instead, we want this:
    ///  ----------------------------------------------------------------
    ///  | slot 0 | slot 1 | slot 2 | slot 3 | slot 4 | slot 5 | slot 6 |
    ///  ----------------------------------------------------------------
    ///  |  11     |   9   |    9   |   10   |   0    |   0    |   0    | = 1,101
    ///      ^---------^--------┘  split the 10 downwards
    ///
    ///  The examples above both have the same total balance, but the second
    ///  example should allow for more efficient payments later down the line.
    ///
    ///  We also try to limit the number of bills in each slot as a secondary
    ///  goal. This is done by recursively exchanging large bills for smaller
    ///  bills and vice versa with rules around how many of each denomination
    ///  to keep. Typically, you never need more than 9 pennies to make any
    ///  payment.
    ///
    ///  Algorithm:
    ///  --------------------------------------------------------------------
    ///  1) First we take large bills and exchange them for smaller bills one
    ///  at a time. We do this recursively until we can't exchange any more
    ///  large bills to small ones. This spreads out our total balance over
    ///  as many slots as possible.
    ///
    ///  2) Then we take smaller bills and exchange them for larger bills if
    ///  we have more than needed in any slot. This reduces the number of
    ///  bills we have in total.
    ///
    ///  This algorithm guarantees that we will never have gaps (zero balance)
    ///  between consecutive slots (e.g. 1000, 0, 10, 1).
    /// ---------------------------------------------------------------------
    ///
    /// TODO: this algorithm could be optimized to reduce the number of
    /// transactions
    mutating func redistribute() -> [InternalExchange] {
        var exchanges: [InternalExchange] = []
        
        exchanges.append(
            contentsOf: exchangeLargeToSmall()
        )
        
        exchanges.append(
            contentsOf: exchangeSmallToLarge()
        )
        
        return exchanges
    }
    
    /// Recursive function to exchange large bills to smaller bills (when
    /// possible). For example, if we have dimes but no pennies, we should
    /// break a dime into pennies.
    ///
    mutating func exchangeLargeToSmall(layer: Int = 0) -> [InternalExchange] {
        //let padding = Array<String>(repeating: "-", count: layer + 1).joined(separator: "").appending("|")
        
        var exchanges: [InternalExchange] = []
        
        for i in 1...slots.count {
            
            let currentSlot = slots[slots.count - i] // Backwards
            let smallerSlot = slotDown(from: currentSlot.type)

            //print("\(padding) o Checking slot: \(currentSlot.type)")
            
            guard let smallerSlot else {
                // We're at the lowest denomination
                // so we can't exchange anymore.
                //print("\(padding) x Last slot")
                break
            }
            
            guard currentSlot.billCount() > 0 else {
                // Nothing to exchange, the current slot is empty.
                //print("\(padding) x Empty")
                continue
            }
            
            let howManyFit = currentSlot.billValue / smallerSlot.billValue
            
            guard smallerSlot.billCount() < howManyFit - 1 else {
                // No reason to exchange yet, the smaller slot
                // already has enough bills for most payments
                //print("\(padding) x Enough bills")
                continue
            }
            
            let amount = Kin(kin: currentSlot.billValue)!
            
            // Adjust the slot balance
            decrement(.bucket(currentSlot.type), kin: amount)
            increment(.bucket(smallerSlot.type), kin: amount)
            
            //print("\(padding) v Exchanging from \(currentSlot.type) to \(smallerSlot.type) \(amount) Kin")
            
            exchanges.append(
                InternalExchange(
                    from: .bucket(currentSlot.type),
                    to: .bucket(smallerSlot.type),
                    kin: amount
                )
            )
            
            exchanges.append(
                contentsOf: exchangeLargeToSmall(layer: layer + 1)
            ) // Recursive
        }
        
        return exchanges
    }
    
    /// Recursive function to exchange small bills to larger bills (when
    /// possible).
    ///
    /// For example, if we have 19 pennies or more, we should exchange excess
    /// pennies for dimes. But if we only have 18 pennies or less, we
    /// should not exchange any because we'd be unable to make a future
    /// payment that has a $0.09 amount (there are some edge cases).
    ///
    mutating func exchangeSmallToLarge(layer: Int = 0) -> [InternalExchange] {
        //let padding = Array<String>(repeating: "-", count: layer + 1).joined(separator: "").appending("|")
        
        var exchanges: [InternalExchange] = []
        
        for i in 0..<slots.count {
            
            let currentSlot = slots[i] // Forwards
            let largerSlot  = slotUp(from: currentSlot.type)

            //print("\(padding) o Checking slot: \(currentSlot.type)")
            
            guard let largerSlot else {
                // We're at the largest denomination
                // so we can't exchange anymore.
                //print("\(padding) x Last slot")
                break
            }
            
            // First we need to check how many bills of the current type fit
            // into the next slot.
            
            let howManyFit = largerSlot.billValue / currentSlot.billValue
            let howManyWeHave = currentSlot.billCount()
            let howManyToLeave = min(howManyFit - 1, howManyWeHave)
            
            guard howManyWeHave >= ((howManyFit * 2) - 1) else {
                // We don't have enough bills to exchange, so we can't do
                // anything in this slot at the moment.
                //print("\(padding) x Not enough bills")
                continue
            }
            
            let howManyToExchange = (howManyWeHave - howManyToLeave) / howManyFit * howManyFit
            let amount = Kin(kin: howManyToExchange)! * currentSlot.billValue
            
            var slotTransfers: [InternalExchange] = []
            
            normalizeLargest(amount: amount) { partialAmount in
                slotTransfers.append(
                    InternalExchange(
                        from: .bucket(currentSlot.type),
                        to: .bucket(largerSlot.type),
                        kin: partialAmount
                    )
                )
            }
            
            // Adjust the slot balance
            decrement(.bucket(currentSlot.type), kin: amount)
            increment(.bucket(largerSlot.type),  kin: amount)
            
//            slotTransfers.forEach { transfer in
//                print("\(padding) v Exchanging from \(transfer.from) to \(transfer.to!) \(transfer.kin) Kin")
//            }
            
            exchanges.append(
                contentsOf: slotTransfers
            )
            
            exchanges.append(
                contentsOf: exchangeSmallToLarge(layer: layer + 1)
            ) // Recursive
        }
        
        return exchanges
    }
    
    // MARK: - Receive -
    
    mutating func receive(from receivingAccount: AccountType, amount: Kin) throws -> [InternalExchange] {
        guard partialBalance(for: receivingAccount) >= amount else {
            throw Error.invalidSlotBalance
        }
        
        var container: [InternalExchange] = []
        
        var remainingAmount = amount
        
        for i in (0..<slots.count).reversed() {
            let currentSlot = slots[i]
            
            let howManyFit = remainingAmount / currentSlot.billValue
            if howManyFit > 0 {
                let amountToDeposit = Kin(kin: howManyFit * currentSlot.billValue)!
                
                normalize(slotType: currentSlot.type, amount: amountToDeposit) { subamount in
                    container.append(
                        InternalExchange(
                            from: receivingAccount,
                            to: .bucket(currentSlot.type),
                            kin: subamount
                        )
                    )
                }
                
                decrement(receivingAccount,          kin: amountToDeposit)
                increment(.bucket(currentSlot.type), kin: amountToDeposit)
                
                remainingAmount = remainingAmount - amountToDeposit
            }
        }
        
        return container
    }
    
    // MARK: - Transfer -
    
    /// This function sends money from the organizer to the outgoing
    /// temporary account. It has to solve the interesting problem of
    /// figuring out which denominations to use when making a payment.
    ///
    /// Unfortunately, this is actually a pretty hard
    /// problem to solve optimally.
    /// https://en.wikipedia.org/wiki/Change-making_problem
    ///
    /// We're going to use the following approach, which should be pretty
    /// good most of the time but definitely has room for improvement.
    /// Specifically, we may want to move from a dynamic programming
    /// solution to a greedy solution in the future.
    ///
    /// Algorithm
    ///
    /// 1. Check the total balance to make sure we have enough to send.
    ///
    /// 2. Try using a naive approach where we send from the amounts
    /// currently in the slots. This will fail if we don't have enough of
    /// a particular bill to pay the amount.
    ///
    /// 3. If step 2 fails, start at the smallest denomination and move
    /// upwards while adding everything along the way until we reach a
    /// denomination that is larger than the remaining amount. Then split
    /// and go backwards... (dynamic programming strategy)
    ///
    mutating func transfer(amount: Kin) throws -> [InternalExchange] {
        guard amount > 0 else {
            throw Error.invalidAmount
        }
        
        guard slotsBalance >= amount else {
            throw Error.insufficientTrayBalance
        }
        
        let startState = self
        do {
            return try withdrawNaively(amount: amount)
        } catch {
            self = startState
            return try withdrawDynamically(amount: amount)
        }
    }
    
    // MARK: - Naive Strategy -
    
    mutating func withdrawNaively(amount: Kin) throws -> [InternalExchange] {
        guard amount > 0 else {
            throw Error.invalidAmount
        }
        
        var container: [InternalExchange] = []
        
        var remainingAmount = amount
        
        // Starting from largest denomination to the smallest
        // we'll find how many 'bills' from each stack we need
        for i in 1...slots.count {
            let slot = slots[slots.count - i] // Backwards
            
            guard slot.partialBalance > 0 else {
                continue
            }
            
            let howManyFit = remainingAmount / slot.billValue
            
            let howMuchToSend = min(slot.partialBalance, Kin(kin: howManyFit * slot.billValue)!)
            if howMuchToSend > 0 {
                guard slot.partialBalance >= howMuchToSend else {
                    throw Error.invalidSlotBalance
                }
                
                let sourceBucket = AccountType.bucket(slot.type)
                
                normalize(slotType: slot.type, amount: howMuchToSend) { amount in
                    container.append(
                        InternalExchange(
                            from: sourceBucket,
                            to: .outgoing,
                            kin: amount
                        )
                    )
                }
                
                decrement(sourceBucket, kin: howMuchToSend)
                increment(.outgoing,    kin: howMuchToSend)
                
                remainingAmount = remainingAmount - howMuchToSend
            }
        }
        
        guard remainingAmount < 1 else {
            throw Error.invalidSlotBalance
        }
        
        return container
    }
    
    // MARK: - Dynamic Strategy -
    
    mutating func withdrawDynamically(amount: Kin) throws -> [InternalExchange] {
        guard amount > 0 else {
            throw Error.invalidAmount
        }
        
        guard slotsBalance >= amount else {
            throw Error.insufficientTrayBalance
        }
        
        let step = try withdrawDynamicallyStep1(amount: amount)
        let exchanges = try withdrawDynamicallyStep2(step: step)
        
        return step.exchanges + exchanges
    }
    
    /// This function assumes that the 'naive strategy' withdrawal was already
    /// attempted. We'll iterate over the slots, from smallest to largest, drain
    /// every slot up to the `amount`. Once a slot that is larger than the
    /// remaining amount is reached, the function returns the index at which the
    /// second step should resume.
    ///
    /// Returns the index that should be broken down in step 2.
    ///
    mutating func withdrawDynamicallyStep1(amount: Kin) throws -> InternalDynamicStep {
        var container: [InternalExchange] = []
        var remaining = amount
        
        for i in 0..<slots.count {
            let currentSlot = slots[i] // Forwards
            
            guard currentSlot.partialBalance > 0 else {
                // Try next slot
                continue
            }
            
            guard remaining >= 1 else {
                // Sent it all
                break
            }
            
            if remaining.truncatedKinValue < currentSlot.billValue {
                // If there's a remaining amount and the current
                // bill value is greater, we'll need to break the
                // current slot bill down to lower slots
                break
            }
            
            let howManyFit = remaining / currentSlot.billValue
            
            let howMuchToSend = min(currentSlot.partialBalance, Kin(kin: howManyFit * currentSlot.billValue)!)
            if howMuchToSend > 0 {
            
                normalize(slotType: currentSlot.type, amount: howMuchToSend) { kinToSend in
                    container.append(
                        InternalExchange(
                            from: .bucket(currentSlot.type),
                            to: .outgoing,
                            kin: kinToSend
                        )
                    )
                }
                
                // Adjust the slot balance
                decrement(.bucket(currentSlot.type), kin: howMuchToSend)
                increment(.outgoing,                 kin: howMuchToSend)
                
                remaining = remaining - howMuchToSend
            }
        }
        
        let index = slots.firstIndex { $0.billValue > remaining.truncatedKinValue && $0.billCount() > 0 }
        
        // Only throw an error if there's a
        // non-zero remaining amount, other
        // wise the first step covered the
        // total amount
        if index == nil && remaining >= 1 {
            throw Error.invalidStepIndex
        }
        
        return InternalDynamicStep(
            remaining: remaining,
            index: index ?? 0, // Zero index will be a no-op in step 2
            exchanges: container
        )
    }
    
    mutating func withdrawDynamicallyStep2(step: InternalDynamicStep) throws -> [InternalExchange] {
        guard step.index > 0 && step.index < slots.count else {
            return []
        }
        
        guard step.remaining >= 1 else {
            return []
        }
        
        var container: [InternalExchange] = []
        var remaining = step.remaining
        
        let current = slots[step.index]
        let lower = slots[step.index - 1]
        
        guard current.billCount() >= 1 else {
            throw Error.slotAtIndexEmpty
        }
        
        // Break the current slot into the lower
        // slot and exchange all the way down
        let initialSplitAmount = Kin(kin: current.billValue)!
        container.append(
            InternalExchange(
                from: .bucket(current.type),
                to: .bucket(lower.type),
                kin: initialSplitAmount
            )
        )
        
        // Adjust the slot balance
        decrement(.bucket(current.type), kin: initialSplitAmount)
        increment(.bucket(lower.type),   kin: initialSplitAmount)
        
        for i in (0...step.index - 1).reversed() {
            let currentSlot = slots[i]
            
            // Split every slot down to the smallest
            // to ensure we have enough bills in each
            if i > 0 {
                let lowerSlot = slots[i - 1]
                let splitAmount = Kin(kin: currentSlot.billValue)!
                container.append(
                    InternalExchange(
                        from: .bucket(currentSlot.type),
                        to: .bucket(lowerSlot.type),
                        kin: splitAmount
                    )
                )
                
                // Adjust the slot balance
                decrement(.bucket(currentSlot.type), kin: splitAmount)
                increment(.bucket(lowerSlot.type),   kin: splitAmount)
            }
            
            let howManyFit = remaining / currentSlot.billValue
            let kinToSend = Kin(kin: howManyFit * currentSlot.billValue)!
            
            guard howManyFit > 0 else {
                continue
            }
            
            guard currentSlot.billCount() >= howManyFit else {
                throw Error.invalidSlotBalance
            }
            
            container.append(
                InternalExchange(
                    from: .bucket(currentSlot.type),
                    to: .outgoing,
                    kin: kinToSend
                )
            )
            
            // Adjust the slot balance
            decrement(.bucket(currentSlot.type), kin: kinToSend)
            increment(.outgoing,                 kin: kinToSend)
            
            remaining = remaining - kinToSend
        }
        
        return container
    }
    
    
    // MARK: - Normalize -
    
    func normalize(slotType: SlotType, amount: Kin, handler: (Kin) -> Void) {
        var howManyFit = amount / slotType.billValue
        while howManyFit > 0 {
            let billsToMove = min(howManyFit, 9)
            let moveAmount = Kin(kin: slotType.billValue * billsToMove)!
            
            handler(moveAmount)
            
            howManyFit = howManyFit - billsToMove
        }
    }
    
    func normalizeLargest(amount: Kin, handler: (Kin) -> Void) {
        var remainingAmount = amount
        
        // Starting from largest denomination to the smallest
        // we'll find how many 'bills' from each stack we need
        for i in 1...slots.count {
            let slot = slots[slots.count - i] // Backwards
            
            var howManyFit = remainingAmount / slot.billValue
            while howManyFit > 0 {
                let billsToMove = min(howManyFit, 9)
                let moveAmount = Kin(kin: slot.billValue * billsToMove)!
                
                handler(moveAmount)
                
                remainingAmount = remainingAmount - moveAmount
                howManyFit = howManyFit - billsToMove
            }
        }
    }
}

// MARK: - Error -

extension Tray {
    enum Error: Swift.Error {
        case invalidAmount
        case insufficientTrayBalance
        case invalidSlotBalance
        case invalidStepIndex
        case slotAtIndexEmpty
    }
}

// MARK: - InternalExchange -

struct InternalExchange: Equatable, Codable, Hashable {
    
    var from: AccountType
    var to: AccountType?
    var kin: Kin
    
    init(from: AccountType, to: AccountType? = nil, kin: Kin) {
        self.from = from
        self.to = to
        self.kin = kin
    }
}

// MARK: - InternalDynamicStep -

struct InternalDynamicStep: Equatable, Codable, Hashable {

    let remaining: Kin
    let index: Int
    let exchanges: [InternalExchange]
    
    init(remaining: Kin, index: Int, exchanges: [InternalExchange]) {
        self.remaining = remaining
        self.index = index
        self.exchanges = exchanges
    }
}

// MARK: - AccountCluster -

private extension AccountCluster {
    static func incoming(for index: Int, mnemonic: MnemonicPhrase) -> AccountCluster {
        AccountCluster(
            index: index,
            authority: .derive(
                using: .bucketIncoming(using: index),
                mnemonic: mnemonic
            )
        )
    }
    
    static func outgoing(for index: Int, mnemonic: MnemonicPhrase) -> AccountCluster {
        AccountCluster(
            index: index,
            authority: .derive(
                using: .bucketOutgoing(using: index),
                mnemonic: mnemonic
            )
        )
    }
}

extension Tray {
    public func prettyPrinted() {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = ""
        f.positivePrefix = ""
        f.negativePrefix = ""
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        
        let accounts = [
            (account: owner,    name: "Primary  "),
            (account: incoming, name: "Incoming "),
            (account: outgoing, name: "Outgoing "),
        ]
        
        let slots = [
            (account: slots[0], name: "1        "),
            (account: slots[1], name: "10       "),
            (account: slots[2], name: "100      "),
            (account: slots[3], name: "1,000    "),
            (account: slots[4], name: "10,000   "),
            (account: slots[5], name: "100,000  "),
            (account: slots[6], name: "1,000,000"),
        ]
        
        print(" --------------------------------------------------------------------------------------------------------------------------------- ")
        print("| Type      | Index |                   State                      |                    Vault                     | Balance       |")
        print(" --------------------------------------------------------------------------------------------------------------------------------- ")
        
        accounts.forEach { account, name in
            print("| \(name) | \(String(account.cluster.index).padded(4))  | \(account.cluster.timelockAccounts.state.publicKey.base58.padded(44)) | \(account.cluster.timelockAccounts.vault.publicKey.base58.padded(44)) | \(f.string(from: NSNumber(value: account.partialBalance.truncatedKinValue))!.padded(13)) |")
        }
        
        slots.forEach { account, name in
            print("| \(name) | \(String(account.cluster.index).padded(4))  | \(account.cluster.timelockAccounts.state.publicKey.base58.padded(44)) | \(account.cluster.timelockAccounts.vault.publicKey.base58.padded(44)) | \(f.string(from: NSNumber(value: account.partialBalance.truncatedKinValue))!.padded(13)) |")
        }
        
        print(" ---------------------------------------------------------------------------------------------------------------------------------")
    }
    
    public func reportableRepresentation() -> [String] {
        [
            string(named: "Primary ", for: owner),
            string(named: "Incoming", for: incoming),
            string(named: "Outgoing", for: outgoing),
            string(named: "1       ", for: slot(for: .bucket1)),
            string(named: "10      ", for: slot(for: .bucket10)),
            string(named: "100     ", for: slot(for: .bucket100)),
            string(named: "1k      ", for: slot(for: .bucket1k)),
            string(named: "10k     ", for: slot(for: .bucket10k)),
            string(named: "100k    ", for: slot(for: .bucket100k)),
            string(named: "1m      ", for: slot(for: .bucket1m)),
        ]
    }
    
    private func string(named name: String, for partialAccount: PartialAccount) -> String {
        "\(name) \(partialAccount.cluster.timelockAccounts.vault.publicKey.base58.padded(44)) \(partialAccount.partialBalance.description)"
    }
    
    private func string(named name: String, for slot: Slot) -> String {
        "\(name) \(slot.cluster.timelockAccounts.vault.publicKey.base58.padded(44)) \(slot.partialBalance.description)"
    }
}

fileprivate extension SlotType {
    var title: String {
        switch self {
        case .bucket1:    return "1    "
        case .bucket10:   return "10   "
        case .bucket100:  return "100  "
        case .bucket1k:   return "1k   "
        case .bucket10k:  return "10k  "
        case .bucket100k: return "100k "
        case .bucket1m:   return "1m   "
        }
    }
}

private extension String {
    func padded(_ minCount: Int) -> String {
        if count < minCount {
            let toInsert = minCount - count
            let padding = Array<String>.init(repeating: " ", count: toInsert).joined(separator: "")
            return "\(self)\(padding)"
        }
        return self
    }
}
