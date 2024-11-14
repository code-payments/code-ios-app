//
//  Limits.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

public struct Limits: Codable, Equatable, Hashable {
    
    /// Date from which the limits are computed
    public let sinceDate: Date
    
    /// Date at which the limits were fetched
    public let fetchDate: Date
    
    /// Maximum quarks that may be deposited at any time. Server will guarantee
    /// this threshold will be below enforced dollar value limits, while also
    /// ensuring sufficient funds are available for a full organizer that supports
    /// max payment sends. Total dollar value limits may be spread across many deposits.
    public let maxDeposit: Kin
    
    public var isStale: Bool {
        Date.now.timeIntervalSince1970 - fetchDate.timeIntervalSince1970 > (60 * 60) // Older than 1 hour
    }
    
    /// Remaining send limits keyed by currency
    private let sendLimits: [CurrencyCode: SendLimit]
    
    /// Buy limits keyed by currency
    private let buyLimits: [CurrencyCode: BuyLimit]
    
    // MARK: - Init -
    
    init(sinceDate: Date, fetchDate: Date, sendLimits: [CurrencyCode: SendLimit], buyLimits: [CurrencyCode: BuyLimit], maxDeposit: Kin) {
        self.sinceDate  = sinceDate
        self.fetchDate  = fetchDate
        self.sendLimits = sendLimits
        self.buyLimits  = buyLimits
        self.maxDeposit = maxDeposit
    }
    
    public func sendLimitFor(currency: CurrencyCode) -> SendLimit? {
        sendLimits[currency]
    }
    
    public func buyLimit(for currency: CurrencyCode) -> BuyLimit? {
        buyLimits[currency]
    }
}

public struct BuyLimit: Codable, Equatable, Hashable {
    
    public static let zero = BuyLimit(max: 0, min: 0)
    
    public let max: Decimal
    public let min: Decimal
    
    public init(max: Decimal, min: Decimal) {
        self.max = max
        self.min = min
    }
}

public struct SendLimit: Codable, Equatable, Hashable {
    
    public static let zero = SendLimit(nextTransaction: 0, maxPerTransaction: 0, maxPerDay: 0)
    
    /// Remaining limit to apply on the next transaction
    public var nextTransaction: Decimal

    /// Maximum allowed on a per-transaction basis
    public var maxPerTransaction: Decimal

    /// Maximum allowed on a per-day basis
    public var maxPerDay: Decimal
    
    public init(nextTransaction: Decimal, maxPerTransaction: Decimal, maxPerDay: Decimal) {
        self.nextTransaction = nextTransaction
        self.maxPerTransaction = maxPerTransaction
        self.maxPerDay = maxPerDay
    }
}

// MARK: - Proto -

extension Limits {
    init(sinceDate: Date, fetchDate: Date, sendLimits: [String: Code_Transaction_V2_SendLimit], buyLimits: [String: Code_Transaction_V2_BuyModuleLimit], deposits: Code_Transaction_V2_DepositLimit) {
        
        let sendDict = sendLimits.mapValues {
            SendLimit(
                nextTransaction: Decimal(Double($0.nextTransaction)),
                maxPerTransaction: Decimal(Double($0.maxPerTransaction)),
                maxPerDay: Decimal(Double($0.maxPerDay))
            )
            
        }
        
        var sendContainer: [CurrencyCode: SendLimit] = [:]
        sendDict.forEach { code, limit in
            if let currency = CurrencyCode(currencyCode: code) {
                sendContainer[currency] = limit
            }
        }
        
        let buyDict = buyLimits.mapValues {
            BuyLimit(
                max: Decimal(Double($0.maxPerTransaction)),
                min: Decimal(Double($0.minPerTransaction))
            )
        }
        
        var buyContainer: [CurrencyCode: BuyLimit] = [:]
        buyDict.forEach { code, limit in
            if let currency = CurrencyCode(currencyCode: code) {
                buyContainer[currency] = limit
            }
        }
        
        self.init(
            sinceDate: sinceDate,
            fetchDate: fetchDate,
            sendLimits: sendContainer,
            buyLimits: buyContainer,
            maxDeposit: Kin(quarks: deposits.maxQuarks)
        )
    }
}

extension Limits {
    public static let empty = Limits(
        sinceDate: .todayAtMidnight(),
        fetchDate: .now,
        sendLimits: [:],
        buyLimits: [:],
        maxDeposit: 0
    )
}
