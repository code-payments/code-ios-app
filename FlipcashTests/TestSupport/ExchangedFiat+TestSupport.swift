//
//  ExchangedFiat+TestSupport.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore

extension ExchangedFiat {

    /// A simple fixture representing a small USDF amount. Use in tests that
    /// only need a well-formed amount — coordinator routing, enum case checks,
    /// and similar tests that do not exercise amount math.
    static let mockOne = ExchangedFiat(
        underlying: 1_000_000,
        converted: 1_000_000,
        mint: .usdf
    )
}
