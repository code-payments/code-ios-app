//
//  CoinbaseOrderEmail.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The email that satisfies the Coinbase onramp's email requirement.
///
/// A server-verified profile email always satisfies it. When the
/// `requireCoinbaseEmailVerification` user flag is off, a locally collected,
/// unverified email is accepted as a fallback. That fallback lives in
/// UserDefaults rather than SQLite because the server never sees it — a
/// `SQLiteVersion` rebuild (which restores only server data) would lose it.
/// It's cleared on logout so it can't leak into another account's orders.
enum CoinbaseOrderEmail {

    @Defaults(.onrampUnverifiedEmail)
    static var unverifiedEmail: String?

    /// The email a Coinbase order may use, or nil when the requirement is
    /// unsatisfied and the verification flow must run. Missing `userFlags`
    /// (not yet fetched) is treated as verification-required.
    static func resolve(
        profile: Profile?,
        userFlags: UserFlags?,
        unverifiedEmail: String? = CoinbaseOrderEmail.unverifiedEmail
    ) -> String? {
        if let verified = profile?.email {
            return verified
        }

        let requiresVerification = userFlags?.requireCoinbaseEmailVerification ?? true
        return requiresVerification ? nil : unverifiedEmail
    }
}
