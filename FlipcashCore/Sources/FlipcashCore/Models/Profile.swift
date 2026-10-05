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

    /// Whether the current username was assigned by the server from the display
    /// name rather than chosen with `SetUsername`. Private: the server sets it
    /// only on the caller's own profile, so it is `false` on anyone else's and
    /// when there is no username.
    public let isUsernameAutoAssigned: Bool

    /// The user's bio, or `nil` when they haven't set one. Public, but absent from a profile
    /// that rides on a chat member row or mention suggestion.
    public let bio: String?

    /// The user's cover picture, or `nil` when they haven't set one. Shares ``ProfilePicture``'s
    /// shape: an original rendition plus a thumbnail.
    public let coverPicture: ProfilePicture?

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

    public init(displayName: String?, phone: String?, email: String?, profilePicture: ProfilePicture? = nil, joinedAt: Date? = nil, tipCardCustomization: TipCardCustomization? = nil, userID: UserID? = nil, username: Username? = nil, minDmChatInitFee: FiatAmount? = nil, isUsernameAutoAssigned: Bool = false, bio: String? = nil, coverPicture: ProfilePicture? = nil) throws {

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
            minDmChatInitFee: minDmChatInitFee,
            isUsernameAutoAssigned: isUsernameAutoAssigned,
            bio: bio,
            coverPicture: coverPicture
        )
    }

    public init(displayName: String?, phone: Phone?, email: String?, profilePicture: ProfilePicture? = nil, joinedAt: Date? = nil, tipCardCustomization: TipCardCustomization? = nil, userID: UserID? = nil, username: Username? = nil, minDmChatInitFee: FiatAmount? = nil, isUsernameAutoAssigned: Bool = false, bio: String? = nil, coverPicture: ProfilePicture? = nil) {
        self.displayName = displayName
        self.phone = phone
        self.email = email
        self.profilePicture = profilePicture
        self.joinedAt = joinedAt
        self.tipCardCustomization = tipCardCustomization
        self.userID = userID
        self.username = username
        self.minDmChatInitFee = minDmChatInitFee
        self.isUsernameAutoAssigned = isUsernameAutoAssigned
        self.bio = bio
        self.coverPicture = coverPicture
    }

    /// `isUsernameAutoAssigned`, `bio` and `coverPicture` are decoded with a default so rows
    /// persisted before they existed still decode, without a `schemaVersion` bump.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        self.phone = try c.decodeIfPresent(Phone.self, forKey: .phone)
        self.email = try c.decodeIfPresent(String.self, forKey: .email)
        self.profilePicture = try c.decodeIfPresent(ProfilePicture.self, forKey: .profilePicture)
        self.joinedAt = try c.decodeIfPresent(Date.self, forKey: .joinedAt)
        self.tipCardCustomization = try c.decodeIfPresent(TipCardCustomization.self, forKey: .tipCardCustomization)
        self.userID = try c.decodeIfPresent(UserID.self, forKey: .userID)
        self.username = try c.decodeIfPresent(Username.self, forKey: .username)
        self.minDmChatInitFee = try c.decodeIfPresent(FiatAmount.self, forKey: .minDmChatInitFee)
        self.isUsernameAutoAssigned = try c.decodeIfPresent(Bool.self, forKey: .isUsernameAutoAssigned) ?? false
        self.bio = try c.decodeIfPresent(String.self, forKey: .bio)
        self.coverPicture = try c.decodeIfPresent(ProfilePicture.self, forKey: .coverPicture)
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
            tipCardCustomization: proto.hasFlipcardCustomization ? TipCardCustomization(proto.flipcardCustomization) : nil,
            userID: proto.hasUserID ? try? UUID(data: proto.userID.value) : nil,
            username: proto.hasUsername ? Username(proto.username) : nil,
            minDmChatInitFee: proto.hasMinDmChatInitFee ? FiatAmount(
                value: Decimal(proto.minDmChatInitFee.nativeAmount),
                currency: try CurrencyCode(currencyCode: proto.minDmChatInitFee.currency)
            ) : nil,
            isUsernameAutoAssigned: proto.isUsernameAutoAssigned,
            // The proto represents an unset bio as an empty string.
            bio: proto.bio.isEmpty ? nil : proto.bio,
            coverPicture: proto.hasCoverPicture ? ProfilePicture(proto.coverPicture) : nil
        )
    }
}

extension TipCardCustomization {
    init(_ proto: Flipcash_Profile_V1_FlipcardCustomization) {
        self.init(colorHex: proto.color.hex)
    }

    /// The customization's colour as the `common.v1.Color` the profile service expects.
    var colorProto: Flipcash_Common_V1_Color {
        .with { $0.hex = colorHex }
    }
}
