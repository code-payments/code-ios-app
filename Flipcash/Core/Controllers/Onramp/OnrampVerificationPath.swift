//
//  OnrampVerificationPath.swift
//  Flipcash
//

import FlipcashCore

/// Navigation path for `VerifyInfoScreen`'s NavigationStack.
enum OnrampVerificationPath: Hashable {
    /// A combined explainer shown first (v2 only) when both phone and email
    /// verification are required — matches Android's verification intro.
    case intro
    case enterPhoneNumber
    case confirmPhoneNumberCode
    case enterEmail
    case confirmEmailCode
}
