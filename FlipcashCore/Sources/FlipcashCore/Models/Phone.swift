//
//  Phone.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
// @preconcurrency: PhoneNumberKit.PhoneNumberUtility not Sendable upstream.
@preconcurrency import PhoneNumberKit

public struct Phone: Codable, Equatable, Hashable, Sendable {

    public let e164: String
    public let national: String

    private let phoneNumber: PhoneNumber

    /// Legacy parse — calls PhoneNumberKit's `parse(_:)` which silently
    /// defaults `withRegion: "US"`. This works for inputs the UI has already
    /// prepended with `+<countryCode>` (e.g. `PhoneVerificationViewModel`
    /// formats input as `+<countryCode><digits>` before constructing
    /// `Phone(_:)`), but bare national-format strings get interpreted as US
    /// numbers regardless of the device's region. For raw inputs that may
    /// be in any device locale (e.g. `CNContactStore.enumerateContacts`),
    /// prefer ``init?(_:defaultRegion:)``.
    public init?(_ string: String) {
        guard let phoneNumber = try? Self.phoneNumberUtility.parse(string) else {
            return nil
        }

        self.phoneNumber = phoneNumber
        self.e164        = Self.phoneNumberUtility.format(phoneNumber, toType: PhoneNumberFormat.e164)
        self.national    = Self.phoneNumberUtility.format(phoneNumber, toType: PhoneNumberFormat.national)
    }

    /// Region-aware parse — accepts both international (`+44 20 1234 5678`)
    /// AND national-format (`020 1234 5678`) strings. National-format strings
    /// are interpreted against `defaultRegion`. Use this for inputs that
    /// arrive without UI mediation — e.g. `CNContactStore.enumerateContacts`
    /// returns raw `stringValue`s in whatever format the user stored them
    /// (typically national-format for the device's own region).
    ///
    /// International-format strings ignore `defaultRegion` and are parsed
    /// using their own prefix, so a UK contact stored as `+44…` on a US
    /// device still parses correctly when `defaultRegion: .us` is passed.
    public init?(_ string: String, defaultRegion: Region) {
        guard let phoneNumber = try? Self.phoneNumberUtility.parse(
            string,
            withRegion: defaultRegion.rawValue.uppercased(),
            ignoreType: true
        ) else {
            return nil
        }

        self.phoneNumber = phoneNumber
        self.e164        = Self.phoneNumberUtility.format(phoneNumber, toType: PhoneNumberFormat.e164)
        self.national    = Self.phoneNumberUtility.format(phoneNumber, toType: PhoneNumberFormat.national)
    }
}

extension Phone: CustomStringConvertible {
    public var description: String {
        e164
    }
}

extension Phone {
    static let phoneNumberUtility = PhoneNumberUtility()
}

public struct PhoneFormatter {
    
    public var currentRegion: Region {
        Region(rawValue: partialFormatter.currentRegion.lowercased())!
    }
    
    private let partialFormatter = PartialFormatter(utility: Phone.phoneNumberUtility, withPrefix: false)
    
    public init() {}
    
    public func countryCode(for region: Region) -> UInt64? {
        Phone.phoneNumberUtility.countryCode(for: region.rawValue)
    }
    
    public func format(_ rawPhoneNumber: String) -> String {
        partialFormatter.formatPartial(rawPhoneNumber)
    }
}
