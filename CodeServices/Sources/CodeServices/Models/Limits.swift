//
//  Limits.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

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
    private let map: [CurrencyCode: Decimal]
    
    // MARK: - Init -
    
    init(sinceDate: Date, fetchDate: Date, map: [CurrencyCode: Decimal], maxDeposit: Kin) {
        self.sinceDate = sinceDate
        self.fetchDate = fetchDate
        self.map = map
        self.maxDeposit = maxDeposit
    }
    
    public func todaysAllowanceFor(currency: CurrencyCode) -> Decimal {
        map[currency] ?? 0
    }
    
    public func multiplying(by value: Decimal) -> Limits {
        Limits(
            sinceDate: sinceDate,
            fetchDate: fetchDate,
            map: map.mapValues { $0 * value },
            maxDeposit: maxDeposit
        )
    }
}

extension Limits {
    public static let empty = Limits(
        sinceDate: .todayAtMidnight(),
        fetchDate: .now(),
        map: [:],
        maxDeposit: 0
    )
}
