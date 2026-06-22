//
//  OwnerKeyStore.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Reads the signed-in user's owner `KeyPair` from the shared keychain
/// access group so that out-of-process extensions (e.g. the notification
/// content extension) can authenticate without access to the main app's
/// private keychain group.
public enum OwnerKeyStore {

    /// The keychain account key under which the owner `UserAccount` is stored.
    /// Must stay in sync with `SecureKey.currentUserAccount.rawValue` in the
    /// main app target.
    public static let ownerAccountKey = "com.flipcash.account.userAccount"

    /// Loads the owner `KeyPair` from the shared keychain access group.
    ///
    /// Returns `nil` when:
    /// - No user is signed in.
    /// - The shared access group can't be resolved at runtime.
    /// - The stored data can't be decoded as a `UserAccount`.
    ///
    /// The notification content extension has no access to the app's
    /// legacy application-identifier group, so there is no fallback read.
    public static func loadOwnerKeyPair() -> KeyPair? {
        guard
            let group = Keychain.sharedAccessGroup,
            let data = Keychain.data(for: ownerAccountKey, accessGroup: group),
            let account = try? JSONDecoder().decode(UserAccount.self, from: data)
        else { return nil }
        return account.keyAccount.owner
    }
}
