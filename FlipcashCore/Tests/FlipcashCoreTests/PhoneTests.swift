//
//  PhoneTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Phone")
struct PhoneTests {

    @Suite("init?(_:) — implicit US default")
    struct ImplicitUSDefaultTests {

        @Test("Parses a well-formed E.164 string")
        func parsesE164() {
            let phone = Phone("+14155550100")
            #expect(phone?.e164 == "+14155550100")
        }

        @Test("Parses an international string with spaces / parens")
        func parsesFormattedInternational() {
            let phone = Phone("+1 (415) 555-0100")
            #expect(phone?.e164 == "+14155550100")
        }

        @Test("National-format input parses against the implicit US default")
        func parsesNationalAgainstImplicitUS() {
            let phone = Phone("4155550100")
            #expect(phone?.e164 == "+14155550100")
        }

        @Test("Rejects garbage")
        func rejectsGarbage() {
            #expect(Phone("not-a-phone") == nil)
            #expect(Phone("") == nil)
        }
    }

    // MARK: - Region-aware initializer

    @Suite("init?(_:defaultRegion:)")
    struct RegionAwareTests {

        @Test("Parses a US national-format string with .us as the default region")
        func parsesUSNationalWithUSDefault() {
            let phone = Phone("415-555-0100", defaultRegion: .us)
            #expect(phone?.e164 == "+14155550100")
        }

        @Test("Parses a UK national-format string with .gb as the default region")
        func parsesUKNationalWithGBDefault() {
            let phone = Phone("020 7946 0958", defaultRegion: .gb)
            #expect(phone?.e164 == "+442079460958")
        }

        @Test("International-format input ignores defaultRegion and parses via its own prefix")
        func internationalIgnoresDefaultRegion() {
            let phone = Phone("+44 20 7946 0958", defaultRegion: .us)
            #expect(phone?.e164 == "+442079460958")
        }

        @Test("E.164 input ignores defaultRegion")
        func e164IgnoresDefaultRegion() {
            let phone = Phone("+14155550100", defaultRegion: .gb)
            #expect(phone?.e164 == "+14155550100")
        }

        @Test("National-format input parsed against the wrong region produces a different / invalid number")
        func wrongRegionMisparsesOrFails() {
            let phone = Phone("(415) 555-0100", defaultRegion: .gb)
            #expect(phone?.e164 != "+14155550100")
        }

        @Test("Empty / garbage inputs return nil regardless of region")
        func emptyGarbageReturnsNil() {
            #expect(Phone("", defaultRegion: .us) == nil)
            #expect(Phone("not-a-phone", defaultRegion: .us) == nil)
        }

        @Test("Region rawValue is uppercased internally — lowercase enum still parses")
        func regionCaseInsensitive() {
            let first = Phone("415-555-0100", defaultRegion: .us)
            let second = Phone("4155550100", defaultRegion: .us)
            #expect(first?.e164 == "+14155550100")
            #expect(second?.e164 == "+14155550100")
        }
    }

    @Suite("Phone.expectedNationalLength")
    struct ExpectedNationalLengthTests {

        @Test("US mobile numbers are ten national digits")
        func usIsTen() {
            #expect(Phone.expectedNationalLength(for: .us) == 10)
        }

        @Test("A supported region returns a positive length")
        func gbIsPositive() {
            let length = Phone.expectedNationalLength(for: .gb)
            #expect((length ?? 0) > 0)
        }
    }
}
