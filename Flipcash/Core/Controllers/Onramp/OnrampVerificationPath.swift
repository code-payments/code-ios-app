//
//  OnrampVerificationPath.swift
//  Flipcash
//

import FlipcashCore

/// Navigation path for `VerifyInfoScreen`'s NavigationStack.
enum OnrampVerificationPath: Hashable {
    case info
    case enterPhoneNumber
    case confirmPhoneNumberCode
    case enterEmail
    case confirmEmailCode
}

extension Profile {
    var canCreateCoinbaseOrder: Bool {
        phone != nil && email?.isEmpty == false
    }
}
