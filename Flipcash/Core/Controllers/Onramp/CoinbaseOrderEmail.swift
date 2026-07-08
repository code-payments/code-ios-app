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
/// The fallback only exists while the `requireCoinbaseEmailVerification`
/// user flag is off — the email flow writes it in skip mode, and
/// `Session.userFlags` drops it whenever fetched flags require verification
/// (logout drops it too). It lives in UserDefaults rather than SQLite
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
}
