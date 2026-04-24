//
//  Session+TestSupport.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore
@testable import Flipcash

extension Session {

    /// A session whose profile is `nil`, so both `isPhoneVerified` and
    /// `isEmailVerified` read as `false`. Use when a test needs to drive
    /// a flow that branches on unverified state. Identical to `Session.mock`
    /// today — kept as a named alias so test intent stays self-documenting.
    @MainActor
    static var unverifiedMock: Session { .mock }

    /// A session with a fully-verified profile (both phone and email set).
    /// Use when a test needs to drive a flow that branches on verified state.
    @MainActor
    static var verifiedMock: Session {
        let session = unverifiedMock
        session.profile = Profile(
            displayName: "Test User",
            phone: .mock,
            email: "test@example.com"
        )
        return session
    }
}
