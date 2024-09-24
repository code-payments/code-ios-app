//
//  Phone.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
@preconcurrency
import PhoneNumberKit

public struct Phone: Codable, Equatable, Hashable, Sendable {
    
    public let e164: String
    public let national: String
    
    private let phoneNumber: PhoneNumber
    
    public var unicodeFlag: String? {
        if let region {
            return Self.unicodeFlagFor(region: region.rawValue)
        }
        return nil
    }
    
    private var region: Region? {
        if let region = phoneNumber.regionID {
            return Region(regionCode: region)!
        }
        return nil
    }
    
    // MARK: - Init -
    
    public init?(_ string: String) {
        guard let phoneNumber = try? Self.phoneNumberKit.parse(string) else {
            return nil
        }
        
        self.phoneNumber = phoneNumber
        self.e164        = Self.phoneNumberKit.format(phoneNumber, toType: .e164)
        self.national    = Self.phoneNumberKit.format(phoneNumber, toType: .national)
    }
    
    // MARK: - Flag -
    
    private static func unicodeFlagFor(region: String) -> String {
        let flagBase: UInt32 = 0x0001F1A5
        return region
            .uppercased()
            .unicodeScalars
            .compactMap { UnicodeScalar(flagBase + $0.value)?.description }
            .joined()
    }
}

extension Phone: CustomStringConvertible {
    public var description: String {
        e164
    }
}

extension Phone {
    static let phoneNumberKit = PhoneNumberKit()
}

public struct PhoneFormatter {
    
    public var currentRegion: Region {
        Region(rawValue: partialFormatter.currentRegion.lowercased())!
    }
    
    private let partialFormatter = PartialFormatter(phoneNumberKit: Phone.phoneNumberKit, withPrefix: false)
    
    public init() {}
    
    public func countryCode(for region: Region) -> UInt64? {
        Phone.phoneNumberKit.countryCode(for: region.rawValue)
    }
    
    public func format(_ rawPhoneNumber: String) -> String {
        partialFormatter.formatPartial(rawPhoneNumber)
    }
}

// MARK: - PhoneDescription -

public struct PhoneDescription: Hashable {
    
    public let phone: Phone
    public let status: RegistraionStatus
    
    init(phone: Phone, status: RegistraionStatus) {
        self.phone = phone
        self.status = status
    }
}

extension PhoneDescription {
    public enum RegistraionStatus: Hashable {
        case uploaded
        case registered
        case invited
        case revoked
    }
}

// MARK: - Mock -

extension Phone {
    public static let mock = Phone("+16472222222")!
}
