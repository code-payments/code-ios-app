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

    /// Parses against PhoneNumberKit's implicit `US` default — national-format
    /// inputs always parse as US numbers. Prefer ``init?(_:defaultRegion:)``
    /// for any input not already prefixed with `+<countryCode>`.
    public init?(_ string: String) {
        guard let phoneNumber = try? Self.phoneNumberUtility.parse(string) else {
            return nil
        }

        self.phoneNumber = phoneNumber
        self.e164        = Self.phoneNumberUtility.format(phoneNumber, toType: PhoneNumberFormat.e164)
        self.national    = Self.phoneNumberUtility.format(phoneNumber, toType: PhoneNumberFormat.national)
    }

    /// Parses national-format strings against `defaultRegion`; international-
    /// format strings ignore it and parse via their own prefix.
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
