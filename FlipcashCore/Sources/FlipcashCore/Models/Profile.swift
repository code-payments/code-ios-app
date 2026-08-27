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

    /// The id of the user this profile belongs to. Server-provided on any
    /// fetched profile, so a caller holding only a handle learns the user's id
    /// from the response; `nil` on a locally-constructed profile.
    public let userID: UserID?

    /// The user's handle on Flipcash, or `nil` when they haven't claimed one.
    /// Public — the server returns it for any user, not just the caller.
    public let username: Username?

    /// The minimum fee another user must pay to initialize a DM chat with this
    /// user. Public — returned for any user, not just the caller. `nil` when
    /// the user hasn't set one, in which case the server default applies.
    public let minDmChatInitFee: FiatAmount?

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

    public init(displayName: String?, phone: String?, email: String?, profilePicture: ProfilePicture? = nil, joinedAt: Date? = nil, tipCardCustomization: TipCardCustomization? = nil, userID: UserID? = nil, username: Username? = nil, minDmChatInitFee: FiatAmount? = nil) throws {

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
            tipCardCustomization: tipCardCustomization,
            userID: userID,
            username: username,
            minDmChatInitFee: minDmChatInitFee
        )
    }

    public init(displayName: String?, phone: Phone?, email: String?, profilePicture: ProfilePicture? = nil, joinedAt: Date? = nil, tipCardCustomization: TipCardCustomization? = nil, userID: UserID? = nil, username: Username? = nil, minDmChatInitFee: FiatAmount? = nil) {
        self.displayName = displayName
        self.phone = phone
        self.email = email
        self.profilePicture = profilePicture
        self.joinedAt = joinedAt
        self.tipCardCustomization = tipCardCustomization
        self.userID = userID
        self.username = username
        self.minDmChatInitFee = minDmChatInitFee
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
            tipCardCustomization: proto.hasTipCardCustomization ? TipCardCustomization(proto.tipCardCustomization) : nil,
            userID: proto.hasUserID ? try? UUID(data: proto.userID.value) : nil,
            username: proto.hasUsername ? Username(proto.username) : nil,
            minDmChatInitFee: proto.hasMinDmChatInitFee ? FiatAmount(
                value: Decimal(proto.minDmChatInitFee.nativeAmount),
                currency: try CurrencyCode(currencyCode: proto.minDmChatInitFee.currency)
            ) : nil
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
