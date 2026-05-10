//
//  CurrencyFormatter.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import os

extension NumberFormatter {
    
    public static func decimal(from string: String) -> Decimal? {
        parse(amount: string)?.decimalValue
    }
    
    public static func parse(amount: String) -> NSNumber? {
        let formatters: [NumberFormatter] = [
            .genericCurrency,
            .genericDecimal,
            .generic
        ]
        
        for formatter in formatters {
            if let number = formatter.number(from: amount) {
                return number
            }
        }
        
        return nil
    }
    
    public static let genericCurrency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f
    }()
    
    public static let genericDecimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
    
    public static let generic: NumberFormatter = {
        NumberFormatter()
    }()
    
    // Configured formatters are cached and reused across callers. ICU
    // locale-data loading on `NumberFormatter()` init was a confirmed
    // main-thread hang source on iOS 17/18 in activity lists that format
    // thousands of rows per render. After first build, instances are never
    // mutated — NumberFormatter reads are thread-safe since iOS 7.
    private struct FiatCacheKey: Hashable {
        let currency: CurrencyCode
        let minimumFractionDigits: Int
        let maximumFractionDigits: Int
        let truncated: Bool
        let suffix: String
    }

    // `NumberFormatter` isn't `Sendable`, but the lock guards every mutation
    // and cached instances are never mutated after first build. Reads are
    // thread-safe per Apple's iOS 7+ contract for `NSFormatter` subclasses.
    private static let fiatCache = OSAllocatedUnfairLock(initialState: [FiatCacheKey: NumberFormatter]())

    public static func fiat(currency: CurrencyCode, minimumFractionDigits: Int = 2, maximumFractionDigits: Int? = nil, truncated: Bool = false, suffix: String? = nil) -> NumberFormatter {
        let resolvedMax = maximumFractionDigits ?? currency.maximumFractionDigits
        let resolvedSuffix = suffix ?? ""
        let key = FiatCacheKey(
            currency: currency,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: resolvedMax,
            truncated: truncated,
            suffix: resolvedSuffix,
        )

        // Fast path: most calls are cache hits.
        if let cached = fiatCache.withLock({ $0[key] }) {
            return cached
        }

        // Slow path: build outside the lock so concurrent misses don't serialize
        // on ICU init. Build is idempotent, so a racy duplicate build is fine —
        // last writer wins and both callers get a valid formatter.
        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .currency
        f.minimumFractionDigits = minimumFractionDigits
        f.maximumFractionDigits = resolvedMax
        f.generatesDecimalNumbers = true
        f.roundingMode = truncated ? .down : .halfUp

        let prefix = currency.singleCharacterCurrencySymbols ?? ""
        f.positivePrefix = prefix
        f.negativePrefix = prefix
        f.positiveSuffix = resolvedSuffix
        f.negativeSuffix = resolvedSuffix

        f.currencySymbol = ""

        return fiatCache.withLock { cache in
            if let existing = cache[key] { return existing }
            cache[key] = f
            return f
        }
    }
}

extension NumberFormatter {
    internal static let kin: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        f.generatesDecimalNumbers = true
        return f
    }()
}

extension NumberFormatter {
    public func string(from decimal: Decimal) -> String? {
        string(from: decimal as NSNumber)
    }
    
    public func string(from integer: UInt64) -> String? {
        string(from: integer as NSNumber)
    }
    
    public func string(byConvertingString value: String) -> String? {
        guard let decimal = Decimal(string: value) else {
            return nil
        }
        
        return string(from: decimal)
    }
}

extension Locale {
    static func currentUsing(currency: CurrencyCode) -> Locale {
        var components = Locale.components(fromIdentifier: Locale.current.identifier)
        components[NSLocale.Key.currencyCode.rawValue] = currency.rawValue
        let identifier = Locale.identifier(fromComponents: components)
        return Locale(identifier: identifier)
    }
}
