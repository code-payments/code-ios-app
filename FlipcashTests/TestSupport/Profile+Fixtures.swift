//
//  Profile+Fixtures.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore

extension Profile {

    /// Profile with both phone and email set so `isPhoneVerified` and
    /// `isEmailVerified` report `true`. Use when a test needs to bypass the
    /// verification gate on a funding operation.
    static let verifiedFixture = Profile(
        displayName: "Test",
        phone: .mock,
        email: "test@test.com"
    )
}
