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

    public static let zero = SendLimit(
        nextTransaction: .zero(in: .usd),
        maxPerTransaction: .zero(in: .usd),
        maxPerDay: .zero(in: .usd)
    )

    /// Remaining limit to apply on the next transaction
    public var nextTransaction: FiatAmount

    /// Maximum allowed on a per-transaction basis
    public var maxPerTransaction: FiatAmount

    /// Maximum allowed on a per-day basis
    public var maxPerDay: FiatAmount

    public init(nextTransaction: FiatAmount, maxPerTransaction: FiatAmount, maxPerDay: FiatAmount) {
        self.nextTransaction = nextTransaction
        self.maxPerTransaction = maxPerTransaction
        self.maxPerDay = maxPerDay
    }
}

// MARK: - Proto -

extension Limits {
    init(proto: Ocp_Transaction_V1_GetLimitsResponse, sinceDate: Date, fetchDate: Date) {

        let container: [CurrencyCode: SendLimit] = Dictionary(uniqueKeysWithValues: proto.sendLimitsByCurrency.compactMap { code, limit in
            guard let currency = try? CurrencyCode(currencyCode: code) else {
                return nil
            }

            let sendLimit = SendLimit(
                nextTransaction: FiatAmount(value: Decimal(Double(limit.nextTransaction)), currency: currency),
                maxPerTransaction: FiatAmount(value: Decimal(Double(limit.maxPerTransaction)), currency: currency),
                maxPerDay: FiatAmount(value: Decimal(Double(limit.maxPerDay)), currency: currency)
            )

            return (currency, sendLimit)
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
