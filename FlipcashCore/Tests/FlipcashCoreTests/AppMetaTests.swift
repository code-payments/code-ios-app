//
//  AppMetaTests.swift
//  FlipcashCoreTests
//

import Testing
@testable import FlipcashCore

@Suite("AppMeta — Info.plist lookups degrade instead of trapping")
struct AppMetaTests {

    // Assertions hold under both hosts: the package test host has no Info.plist and gets the
    // stand-in, the app target has one and gets the real value.

    @Test("Version reads without trapping and is never empty")
    func versionDegrades() {
        #expect(!AppMeta.version.isEmpty)
    }

    @Test("Build reads without trapping and is never empty")
    func buildDegrades() {
        #expect(!AppMeta.build.isEmpty)
    }

    @Test("The build stand-in stays unparseable, so requiresUpgrade allows access")
    func buildStandInIsNotNumeric() {
        #expect(UInt32(AppMeta.unknown) == nil)
    }
}
