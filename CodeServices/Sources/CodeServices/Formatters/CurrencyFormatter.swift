//
//  CurrencyFormatter.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

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
    
    public static func fiat(currency: CurrencyCode, minimumFractionDigits: Int = 2, truncated: Bool = false, suffix: String? = nil) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = currency == .kin ? 0 : minimumFractionDigits
        f.maximumFractionDigits = minimumFractionDigits
        f.generatesDecimalNumbers = true
        f.roundingMode = truncated ? .down : .halfDown
        
        let prefix = currency.singleCharacterCurrencySymbols ?? ""
        let suffix = (suffix ?? "")
        
        f.positivePrefix = prefix
        f.negativePrefix = prefix
        f.positiveSuffix = suffix
        f.negativeSuffix = suffix
        
        f.currencySymbol = ""
        
        return f
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
    static func currentUsing(currency: CodeServices.CurrencyCode) -> Locale {
        var components = Locale.components(fromIdentifier: Locale.current.identifier)
        components[NSLocale.Key.currencyCode.rawValue] = currency.rawValue
        let identifier = Locale.identifier(fromComponents: components)
        return Locale(identifier: identifier)
    }
}
