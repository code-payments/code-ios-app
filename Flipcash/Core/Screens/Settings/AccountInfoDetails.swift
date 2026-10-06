//
//  AccountInfoDetails.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The rows on the Account Info screen, built from the account's identity.
///
/// Named `AccountInfoDetails` because `AccountInfo` is already the on-chain
/// token-account model in FlipcashCore.
nonisolated struct AccountInfoDetails {

    /// One copyable line on Account Info: what the row shows, and what a tap
    /// puts on the clipboard when the two differ.
    struct Row: Hashable {
        let title: String
        let display: String
        let copyValue: String
        let accessibilityID: String
    }

    /// Phone and email only when the profile has them, then the account ID and
    /// the owner authority's public key.
    static func rows(profile: Profile?, userID: UserID, authority: PublicKey) -> [Row] {
        var rows: [Row] = []

        if let phone = profile?.phone {
            rows.append(Row(
                title: "Phone",
                display: phone.national,
                copyValue: phone.e164,
                accessibilityID: "account-info-phone"
            ))
        }

        if let email = profile?.email, !email.isEmpty {
            rows.append(Row(
                title: "Email",
                display: email,
                copyValue: email,
                accessibilityID: "account-info-email"
            ))
        }

        rows.append(Row(
            title: "Account ID",
            display: userID.uuidString,
            copyValue: userID.uuidString,
            accessibilityID: "account-info-account-id"
        ))

        rows.append(Row(
            title: "Public Key",
            display: authority.base58,
            copyValue: authority.base58,
            accessibilityID: "account-info-public-key"
        ))

        return rows
    }
}
