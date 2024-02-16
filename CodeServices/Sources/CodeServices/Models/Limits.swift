//
//  Limits.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

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
        Date.now().timeIntervalSince1970 - fetchDate.timeIntervalSince1970 > (60 * 60) // Older than 1 hour
    }
    
    /// Remaining send limits keyed by currency
    private let sendLimits: [CurrencyCode: Decimal]
    
    /// Buy limits keyed by currency
    private let buyLimits: [CurrencyCode: Limit]
    
    // MARK: - Init -
    
    init(sinceDate: Date, fetchDate: Date, sendLimits: [CurrencyCode: Decimal], buyLimits: [CurrencyCode: Limit], maxDeposit: Kin) {
        self.sinceDate  = sinceDate
        self.fetchDate  = fetchDate
        self.sendLimits = sendLimits
        self.buyLimits  = buyLimits
        self.maxDeposit = maxDeposit
    }
    
    public func todaysAllowanceFor(currency: CurrencyCode) -> Decimal {
        sendLimits[currency] ?? 0
    }
    
    public func multiplying(by value: Decimal) -> Limits {
        Limits(
            sinceDate: sinceDate,
            fetchDate: fetchDate,
            sendLimits: sendLimits.mapValues { $0 * value },
            buyLimits: buyLimits,
            maxDeposit: maxDeposit
        )
    }
    
    public func buyLimit(for currency: CurrencyCode) -> Limit? {
        buyLimits[currency]
    }
}

public struct Limit: Codable, Equatable, Hashable {
    
    public static let zero = Limit(max: 0, min: 0)
    
    public let max: Decimal
    public let min: Decimal
    
    public init(max: Decimal, min: Decimal) {
        self.max = max
        self.min = min
    }
}

// MARK: - Proto -

extension Limits {
    init(sinceDate: Date, fetchDate: Date, sendLimits: [String: Code_Transaction_V2_SendLimit], buyLimits: [String: Code_Transaction_V2_BuyModuleLimit], deposits: Code_Transaction_V2_DepositLimit) {
        
        let sendDict = sendLimits.mapValues { Decimal(Double($0.nextTransaction)) }
        var sendContainer: [CurrencyCode: Decimal] = [:]
        sendDict.forEach { code, limit in
            if let currency = CurrencyCode(currencyCode: code) {
                sendContainer[currency] = limit
            }
        }
        
        let buyDict = buyLimits.mapValues {
            Limit(
                max: Decimal(Double($0.maxPerTransaction)),
                min: Decimal(Double($0.minPerTransaction))
            )
        }
        
        var buyContainer: [CurrencyCode: Limit] = [:]
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
        fetchDate: .now(),
        sendLimits: [:],
        buyLimits: [:],
        maxDeposit: 0
    )
}
