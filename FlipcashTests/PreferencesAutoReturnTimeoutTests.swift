//
//  PreferencesAutoReturnTimeoutTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-08.
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

// Tests share UserDefaults.standard[autoReturnTimeout]; .serialized enforces
// in-suite ordering. If another test target adds a writer for the same key,
// promote this to a tag-based serial group.
@MainActor
@Suite("Preferences AutoReturnTimeout", .serialized)
struct PreferencesAutoReturnTimeoutTests {

    private static let defaultsKey = DefaultsKey.autoReturnTimeout.rawValue

    private static func clearKey() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - AutoReturnTimeout core values -

    @Test("fiveMinutes duration is 300 seconds")
    func fiveMinutesDuration() {
        #expect(AutoReturnTimeout.fiveMinutes.duration == 300)
    }

    @Test("tenMinutes duration is 600 seconds")
    func tenMinutesDuration() {
        #expect(AutoReturnTimeout.tenMinutes.duration == 600)
    }

    @Test("never duration is nil")
    func neverDuration() {
        #expect(AutoReturnTimeout.never.duration == nil)
    }

    @Test("displayName values match iOS Auto-Lock copy")
    func displayNames() {
        #expect(AutoReturnTimeout.fiveMinutes.displayName == "5 Minutes")
        #expect(AutoReturnTimeout.tenMinutes.displayName == "10 Minutes")
        #expect(AutoReturnTimeout.never.displayName == "Never")
    }

    // MARK: - Preferences persistence -

    @Test("default value when no key has been written is fiveMinutes")
    func autoReturnTimeout_noKeyPresent_returnsFiveMinutes() {
        Self.clearKey()
        defer { Self.clearKey() }

        let preferences = Preferences()

        #expect(preferences.autoReturnTimeout == .fiveMinutes)
    }

    @Test("persisting tenMinutes round-trips through a fresh Preferences")
    func autoReturnTimeout_persistTenMinutes_roundTripsAcrossInstances() {
        Self.clearKey()
        defer { Self.clearKey() }

        let writer = Preferences()
        writer.autoReturnTimeout = .tenMinutes

        let reader = Preferences()

        #expect(reader.autoReturnTimeout == .tenMinutes)
    }

    @Test("persisting never round-trips through a fresh Preferences")
    func autoReturnTimeout_persistNever_roundTripsAcrossInstances() {
        Self.clearKey()
        defer { Self.clearKey() }

        let writer = Preferences()
        writer.autoReturnTimeout = .never

        let reader = Preferences()

        #expect(reader.autoReturnTimeout == .never)
    }
}
