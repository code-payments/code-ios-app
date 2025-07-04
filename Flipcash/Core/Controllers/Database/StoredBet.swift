//
//  StoredBet.swift
//  Code
//
//  Created by Dima Bart on 2025-07-04.
//

import Foundation
import FlipcashCore

struct StoredBet: Identifiable, Sendable, Equatable, Hashable {
    let id: PublicKey
    let userID: UserID
    let payoutDestination: PublicKey
    let betDate: Date
    let selectedOutcome: PoolResoltion
    
    let isFulfilled: Bool
    
    init(id: PublicKey, userID: UserID, payoutDestination: PublicKey, betDate: Date, selectedOutcome: PoolResoltion, isFulfilled: Bool) {
        self.id = id
        self.userID = userID
        self.payoutDestination = payoutDestination
        self.betDate = betDate
        self.selectedOutcome = selectedOutcome
        self.isFulfilled = isFulfilled
    }
}
