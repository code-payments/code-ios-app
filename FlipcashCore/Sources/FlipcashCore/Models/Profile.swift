//
//  Profile.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-08-21.
//

import Foundation
import FlipcashAPI

public struct Profile: Codable, Equatable, Sendable {
    
    public static let empty = Profile(
        displayName: nil,
        phone: Optional<Phone>.none,
        email: nil
    )
    
    public let displayName: String?
    public let phone: Phone?
    public let email: String?
    public let profilePicture: ProfilePicture?

    public var isPhoneVerified: Bool {
        phone != nil
    }

    /// Returns whether this profile can receive tips — both a name and a
    /// picture are required.
    public var isTippable: Bool {
        displayName?.isEmpty == false && profilePicture != nil
    }

    /// Returns whether this profile gained a phone number not present in `previous`.
    public func hasNewlyLinkedPhone(since previous: Profile?) -> Bool {
        phone != nil && phone?.e164 != previous?.phone?.e164
    }

    public init(displayName: String?, phone: String?, email: String?, profilePicture: ProfilePicture? = nil) throws {

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
            email: normalizedEmail,
            profilePicture: profilePicture
        )
    }

    public init(displayName: String?, phone: Phone?, email: String?, profilePicture: ProfilePicture? = nil) {
        self.displayName = displayName
        self.phone = phone
        self.email = email
        self.profilePicture = profilePicture
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
            email: proto.emailAddress.value,
            profilePicture: proto.hasProfilePicture ? ProfilePicture(proto.profilePicture) : nil
        )
    }
}
