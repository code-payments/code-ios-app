//
//  Limits.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

public struct Limits: Codable, Equatable, Hashable, Sendable {
    
    /// Date from which the limits are computed
    public let sinceDate: Date
    
    /// Date at which the limits were fetched
    public let fetchDate: Date
    
    public var isStale: Bool {
        Date.now.timeIntervalSince1970 - fetchDate.timeIntervalSince1970 > (60 * 15) // Older than 15 min
    }
    
    /// Remaining send limits keyed by currency
    private let sendLimits: [CurrencyCode: SendLimit]
    
    // MARK: - Init -
    
    init(sinceDate: Date, fetchDate: Date, sendLimits: [CurrencyCode: SendLimit]) {
        self.sinceDate  = sinceDate
        self.fetchDate  = fetchDate
        self.sendLimits = sendLimits
    }
    
    public func sendLimitFor(currency: CurrencyCode) -> SendLimit? {
        sendLimits[currency]
    }
}

public struct SendLimit: Codable, Equatable, Hashable, Sendable {
    
    public static let zero = SendLimit(nextTransaction: 0, maxPerTransaction: 0, maxPerDay: 0)
    
    /// Remaining limit to apply on the next transaction
    public var nextTransaction: Quarks

    /// Maximum allowed on a per-transaction basis
    public var maxPerTransaction: Quarks

    /// Maximum allowed on a per-day basis
    public var maxPerDay: Quarks
    
    public init(nextTransaction: Quarks, maxPerTransaction: Quarks, maxPerDay: Quarks) {
        self.nextTransaction = nextTransaction
        self.maxPerTransaction = maxPerTransaction
        self.maxPerDay = maxPerDay
    }
}

// MARK: - Proto -

extension Limits {
    init(proto: Ocp_Transaction_V1_GetLimitsResponse, sinceDate: Date, fetchDate: Date) {
        
        let decimals = PublicKey.usdf.mintDecimals

        let container: [CurrencyCode: SendLimit] = Dictionary(uniqueKeysWithValues: proto.sendLimitsByCurrency.compactMap { code, limit in
            guard let currency = try? CurrencyCode(currencyCode: code) else {
                return nil
            }
            
            let nextTransaction = try! Quarks(
                fiatDecimal: Decimal(Double(limit.nextTransaction)),
                currencyCode: currency,
                decimals: decimals
            )
            
            let maxPerTransaction = try! Quarks(
                fiatDecimal: Decimal(Double(limit.maxPerTransaction)),
                currencyCode: currency,
                decimals: decimals
            )
            
            let maxPerDay = try! Quarks(
                fiatDecimal: Decimal(Double(limit.maxPerDay)),
                currencyCode: currency,
                decimals: decimals
            )
            
            let limit = SendLimit(
                nextTransaction: nextTransaction,
                maxPerTransaction: maxPerTransaction,
                maxPerDay: maxPerDay
            )
            
            return (currency, limit)
        })
        
        self.init(
            sinceDate: sinceDate,
            fetchDate: fetchDate,
            sendLimits: container
        )
    }
}

extension Limits {
    public static let empty = Limits(
        sinceDate: .todayAtMidnight(),
        fetchDate: .now,
        sendLimits: [:]
    )
}
