//
//  UserFlags+Fixtures.swift
//  FlipcashTests
//

import Foundation
@testable import FlipcashCore

extension UserFlags {

    /// Baseline flags fixture — override only what the test cares about.
    static func fixture(
        requireCoinbaseEmailVerification: Bool = false
    ) -> UserFlags {
        UserFlags(
            isRegistered: true,
            isStaff: false,
            onrampProviders: [],
            preferredOnrampProvider: .unknown,
            minBuildNumber: 0,
            billExchangeDataTimeout: nil,
            newCurrencyPurchaseAmount: .zero(mint: .usdf),
            newCurrencyFeeAmount: .zero(mint: .usdf),
            withdrawalFeeAmount: .zero(mint: .usdf),
            minimumHolderValue: .zero(mint: .usdf),
            enablePhoneNumberSend: false,
            requireCoinbaseEmailVerification: requireCoinbaseEmailVerification
        )
    }
}
