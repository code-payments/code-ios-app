//
//  BetaFlags+TestSupport.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
@testable import Flipcash

extension BetaFlags {

    /// Runs `body` with every option stored on in `UserDefaults.standard`, as a test host can have
    /// them, then puts the stored options and applied defaults back. Requires first that a plain
    /// ``BetaFlags`` reads every option on, so a guard built on this cannot pass because the store
    /// did not take.
    ///
    /// Not async, so nothing else on the main actor reads the store between the write and the
    /// restore.
    static func withEveryOptionStored(
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: () throws -> Void
    ) throws {
        var storedOptions = Defaults<Set<String>>(.betaFlags)
        var appliedDefaults = Defaults<Set<String>>(.appliedBetaFlagDefaults)
        let savedOptions = storedOptions.wrappedValue
        let savedDefaults = appliedDefaults.wrappedValue
        defer {
            storedOptions.wrappedValue = savedOptions
            appliedDefaults.wrappedValue = savedDefaults
        }
        storedOptions.wrappedValue = Set(Option.allCases.map(\.rawValue))

        let stored = BetaFlags()
        try #require(
            Option.allCases.allSatisfy { stored.hasEnabled($0) },
            "every flag reads on from the store",
            sourceLocation: sourceLocation
        )
        try body()
    }
}
