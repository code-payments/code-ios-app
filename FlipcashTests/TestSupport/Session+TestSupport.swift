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
    /// a flow that branches on unverified state.
    @MainActor
    static func makeUnverifiedMock() -> Session {
        Session(
            container: .mock,
            historyController: .mock,
            ratesController: .mock,
            database: .mock,
            keyAccount: .mock,
            owner: .init(
                authority: .derive(using: .primary(), mnemonic: .mock),
                mint: .mock,
                timeAuthority: .usdcAuthority
            ),
            userID: UUID()
        )
    }

    /// A session with a fully-verified profile (both phone and email set).
    /// Use when a test needs to drive a flow that branches on verified state.
    @MainActor
    static func makeVerifiedMock() -> Session {
        let session = makeUnverifiedMock()
        session.profile = Profile(
            displayName: "Test User",
            phone: .mock,
            email: "test@example.com"
        )
        return session
    }

    /// Alias for `makeUnverifiedMock()` — exposes the session as a property so
    /// tests read as `.unverifiedMock` at the call site.
    @MainActor
    static var unverifiedMock: Session {
        makeUnverifiedMock()
    }

    /// Alias for `makeVerifiedMock()` — exposes the session as a property so
    /// tests read as `.verifiedMock` at the call site.
    @MainActor
    static var verifiedMock: Session {
        makeVerifiedMock()
    }
}
