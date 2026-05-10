//
//  Profile.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-08-21.
//

import Foundation
import FlipcashAPI

public struct Profile: Equatable, Sendable {
    
    public static let empty = Profile(
        displayName: nil,
        phone: Optional<Phone>.none,
        email: nil
    )
    
    public let displayName: String?
    public let phone: Phone?
    public let email: String?
    
    public var isPhoneVerified: Bool {
        phone != nil
    }
    
    public var isEmailVerified: Bool {
        (email?.count ?? 0) > 0
    }
    
    public init(displayName: String?, phone: String?, email: String?) throws {

        // Only parse phone if it's not empty
        var parsedPhone: Phone?
        if let phone = phone, !phone.isEmpty {
            guard let p = Phone(phone) else {
                throw Error.failedToParsePhoneNumber
            }

            parsedPhone = p
        }

        // Proto represents "unset" email as an empty string; normalize to nil
        // so downstream `email == nil` checks behave the same for phone and email.
        let normalizedEmail: String? = (email?.isEmpty == false) ? email : nil

        self.init(
            displayName: displayName,
            phone: parsedPhone,
            email: normalizedEmail
        )
    }
    
    public init(displayName: String?, phone: Phone?, email: String?) {
        self.displayName = displayName
        self.phone = phone
        self.email = email
    }
}

extension Profile {
    enum Error: Swift.Error {
        case failedToParsePhoneNumber
    }
}

// MARK: - Proto -

extension Profile {
    init(_ proto: Flipcash_Profile_V1_UserProfile) throws {
        try self.init(
            displayName: proto.displayName,
            phone: proto.phoneNumber.value,
            email: proto.emailAddress.value
        )
    }
}
