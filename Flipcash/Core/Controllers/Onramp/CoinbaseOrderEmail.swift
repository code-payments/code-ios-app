//
//  CoinbaseOrderEmail.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The email that satisfies the Coinbase onramp's email requirement: the
/// server-verified profile email, falling back to a locally collected,
/// unverified one.
///
/// The email flow writes the fallback when `requireCoinbaseEmailVerification`
/// is off; logout clears it. It lives in UserDefaults rather than SQLite
/// because the server never sees it — a `SQLiteVersion` rebuild (which
/// restores only server data) would lose it.
enum CoinbaseOrderEmail {

    @Defaults(.onrampUnverifiedEmail)
    static var unverifiedEmail: String?

    /// The email a Coinbase order may use, or nil when the requirement is
    /// unsatisfied and the verification flow must run.
    static func resolve(
        profile: Profile?,
        unverifiedEmail: String? = CoinbaseOrderEmail.unverifiedEmail
    ) -> String? {
        profile?.email ?? unverifiedEmail
    }

    /// The contact pair a Coinbase order requires, or nil when either half
    /// is missing and the verification flow must run.
    static func resolveContact(profile: Profile?) -> (email: String, phone: String)? {
        guard let email = resolve(profile: profile),
              let phone = profile?.phone?.e164 else {
            return nil
        }
        return (email, phone)
    }
}
