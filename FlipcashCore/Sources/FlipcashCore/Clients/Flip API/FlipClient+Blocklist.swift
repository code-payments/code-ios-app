//
//  FlipClient+Blocklist.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

extension FlipClient {

    /// Adds a user to the caller's blocklist.
    public func blockUser(userID: UserID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            blocklistService.blockUser(userID: userID, owner: owner) { c.resume(with: $0) }
        }
    }

    /// Removes a user from the caller's blocklist.
    public func unblockUser(userID: UserID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            blocklistService.unblockUser(userID: userID, owner: owner) { c.resume(with: $0) }
        }
    }

    /// Pages the blocklist to exhaustion, most-recently-blocked first.
    public func getBlocklist(owner: KeyPair) async throws -> [BlockedUserEntry] {
        var all: [BlockedUserEntry] = []
        var pagingToken: Data?
        // Loop until the server signals no further pages via hasMore/pagingToken.
        while true {
            let page = try await withCheckedThrowingContinuation { (c: CheckedContinuation<BlocklistPage, Error>) in
                blocklistService.getBlocklist(owner: owner, pagingToken: pagingToken) { c.resume(with: $0) }
            }
            all.append(contentsOf: page.blockedUsers)
            if !page.hasMore { break }
            pagingToken = page.pagingToken
        }
        return all
    }
}
