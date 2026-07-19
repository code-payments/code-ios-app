//
//  Bug+TestSupport.swift
//  FlipcashTests
//

import Testing

extension Trait where Self == Bug {
    /// The iOS 27 navigation-bar autolayout wedge behind the Wallet ↔
    /// Currency Info app hang. Tests carrying this trait pin the churn
    /// removal that starves the OS bug; the linked Bugsnag issue is the
    /// sentinel for re-checking newer iOS 27 builds.
    static var currencyInfoAppHang: Self {
        .bug(
            "https://app.bugsnag.com/flipcash/flipcash-ios/errors/6a55066bfdca5cb0d6c31b53",
            "iOS 27 nav-bar autolayout wedge (Wallet ↔ Currency Info app hang)"
        )
    }
}
