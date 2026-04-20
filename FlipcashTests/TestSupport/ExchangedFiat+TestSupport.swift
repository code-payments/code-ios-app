//
//  ExchangedFiat+TestSupport.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore

extension ExchangedFiat {

    /// A $1 USDF fixture (USDF uses 6 decimals, so $1 == 1_000_000 quarks).
    /// Use in tests that only need a well-formed amount — coordinator routing,
    /// enum case checks, and similar tests that do not exercise amount math.
    static let mockOne = ExchangedFiat(
        underlying: 1_000_000,
        converted: 1_000_000,
        mint: .usdf
    )
}
