//
//  PhoneTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Phone")
struct PhoneTests {

    // MARK: - Legacy implicit-US-default initializer

    /// `Phone(_:)` calls PhoneNumberKit's `parse(_:)` which silently defaults
    /// `withRegion: "US"`. So bare national-format strings DO parse — but
    /// always as US numbers, which is wrong for non-US users. This is the
    /// motivation for the `init?(_:defaultRegion:)` overload below.
    /// `PhoneVerificationViewModel` works around the issue by pre-formatting
    /// input as `+<countryCode><digits>` before constructing `Phone(_:)`.
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
            // Surprise behavior — `parse(_:)` defaults to `withRegion: \"US\"`,
            // so a bare local-format string IS accepted, just always
            // interpreted as a US number. Wrong for non-US users; correct
            // when the UI has already validated the country (the existing
            // verification flow).
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
            // UK landline: 020 7946 0958 is the BBC-style example number for
            // London (+44 20 7946 0958 in E.164).
            let phone = Phone("020 7946 0958", defaultRegion: .gb)
            #expect(phone?.e164 == "+442079460958")
        }

        @Test("International-format input ignores defaultRegion and parses via its own prefix")
        func internationalIgnoresDefaultRegion() {
            // A UK number stored as `+44 ...` on a US device must still parse
            // as UK, not be misinterpreted as US.
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
            // US-style `(415) 555-0100` parsed against UK region: PhoneNumberKit
            // will either fail to parse or produce a non-US number. Either way
            // it must NOT round-trip to the correct US e164. The test asserts
            // the loose property: the result isn't the US e164.
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
            // Region.rawValue is lowercase (`us`, `gb`); PhoneNumberKit expects
            // ISO 3166-1 alpha-2 uppercase. The initializer uppercases
            // internally — verify by parsing the same number twice with
            // .us and confirming consistent output.
            let first = Phone("415-555-0100", defaultRegion: .us)
            let second = Phone("4155550100", defaultRegion: .us)
            #expect(first?.e164 == "+14155550100")
            #expect(second?.e164 == "+14155550100")
        }
    }
}
