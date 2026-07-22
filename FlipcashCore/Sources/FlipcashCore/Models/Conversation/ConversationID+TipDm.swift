//
//  ConversationID+TipDm.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

extension ConversationID {

    /// Returns the canonical tip-DM chat ID between two users.
    ///
    /// Mirrors the server's `MustDeriveDmChatID(TIP_DM, a, b)` byte-for-byte —
    /// SHA-256 over the TIP_DM domain and the sorted member set — and the
    /// server rejects any tip intent whose chat id doesn't match it.
    public static func tipDm(between a: UserID, and b: UserID) -> ConversationID {
        // Sorted set of the participants' raw ID bytes; a self-pair collapses
        // to a single member, matching the server's derivation.
        var members = [a.data, b.data].sorted { $0.lexicographicallyPrecedes($1) }
        if members[0] == members[1] {
            members.removeLast()
        }

        var hash = SHA256()
        hash.update(Data("flipcash:chat:dm:2".utf8))
        for member in members {
            hash.update(member)
        }
        return ConversationID(data: Data(hash.digestBytes()))
    }
}
