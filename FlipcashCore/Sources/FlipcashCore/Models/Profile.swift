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
        email: nil,
        joinedAt: nil
    )

    public let displayName: String?
    public let phone: Phone?
    public let email: String?
    public let profilePicture: ProfilePicture?

    /// The date the user joined Flipcash, or `nil` when the server did not supply one.
    public let joinedAt: Date?

    /// How the user has customized their Tip Card. `nil` when the server did not
    /// supply one (older responses); otherwise always populated — the server
    /// resolves defaults for anything the user hasn't customized.
    public let tipCardCustomization: TipCardCustomization?

    public var isPhoneVerified: Bool {
        phone != nil
    }

    /// Returns whether this profile can receive tips — only a display name is
    /// required. A profile picture is not part of onboarding, so requiring one
    /// left every name-only profile non-tippable and bounced Tips back to the
    /// intro screen on reopen.
    public var isTippable: Bool {
        displayName?.isEmpty == false
    }

    /// Returns whether this profile gained a phone number not present in `previous`.
    public func hasNewlyLinkedPhone(since previous: Profile?) -> Bool {
        phone != nil && phone?.e164 != previous?.phone?.e164
    }

    public init(displayName: String?, phone: String?, email: String?, profilePicture: ProfilePicture? = nil, joinedAt: Date? = nil, tipCardCustomization: TipCardCustomization? = nil) throws {

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
            profilePicture: profilePicture,
            joinedAt: joinedAt,
            tipCardCustomization: tipCardCustomization
        )
    }

    public init(displayName: String?, phone: Phone?, email: String?, profilePicture: ProfilePicture? = nil, joinedAt: Date? = nil, tipCardCustomization: TipCardCustomization? = nil) {
        self.displayName = displayName
        self.phone = phone
        self.email = email
        self.profilePicture = profilePicture
        self.joinedAt = joinedAt
        self.tipCardCustomization = tipCardCustomization
    }
}

/// How a user has customized their Tip Card. Public — returned for any user,
/// not just the caller.
public struct TipCardCustomization: Codable, Equatable, Sendable {

    /// The Tip Card colour as an RGB hex string (e.g. "#19191A").
    public let colorHex: String

    public init(colorHex: String) {
        self.colorHex = colorHex
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
            profilePicture: proto.hasProfilePicture ? ProfilePicture(proto.profilePicture) : nil,
            joinedAt: proto.hasJoinTs ? proto.joinTs.date : nil,
            tipCardCustomization: proto.hasTipCardCustomization ? TipCardCustomization(proto.tipCardCustomization) : nil
        )
    }
}

extension TipCardCustomization {
    init(_ proto: Flipcash_Profile_V1_TipCardCustomization) {
        self.init(colorHex: proto.color.hex)
    }

    /// The customization's colour as the `common.v1.Color` the profile service expects.
    var colorProto: Flipcash_Common_V1_Color {
        .with { $0.hex = colorHex }
    }
}
