//
//  CoinbaseOrderEmail.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The email that satisfies the Coinbase onramp's email requirement.
///
/// When `requireCoinbaseEmailVerification` is on, only a profile email the
/// server marks verified counts; an email linked without a code does not.
/// When it is off, any profile email counts, falling back to a locally
/// collected, unverified one.
///
/// The email flow writes the fallback when `requireCoinbaseEmailVerification`
/// is off; logout clears it. It lives in UserDefaults rather than SQLite
/// because the server never sees it — a `schemaVersion` rebuild (which
/// restores only server data) would lose it.
enum CoinbaseOrderEmail {

    @Defaults(.onrampUnverifiedEmail)
    static var unverifiedEmail: String?

    /// The email a Coinbase order may use, or nil when the requirement is
    /// unsatisfied and the verification flow must run.
    static func resolve(
        profile: Profile?,
        requiresVerification: Bool,
        unverifiedEmail: String? = CoinbaseOrderEmail.unverifiedEmail
    ) -> String? {
        guard requiresVerification else {
            return profile?.email ?? unverifiedEmail
        }
        guard let profile, profile.isEmailAddressVerified else {
            return nil
        }
        return profile.email
    }

    /// The contact pair a Coinbase order requires, or nil when either half
    /// is missing and the verification flow must run.
    static func resolveContact(profile: Profile?, requiresVerification: Bool) -> (email: String, phone: String)? {
        guard let email = resolve(profile: profile, requiresVerification: requiresVerification),
              let phone = profile?.phone?.e164 else {
            return nil
        }
        return (email, phone)
    }
}

extension Session {

    /// Whether a Coinbase order needs a server-verified email. Flags that have
    /// not loaded count as required, the stricter reading.
    var requiresCoinbaseEmailVerification: Bool {
        userFlags?.requireCoinbaseEmailVerification ?? true
    }
}
