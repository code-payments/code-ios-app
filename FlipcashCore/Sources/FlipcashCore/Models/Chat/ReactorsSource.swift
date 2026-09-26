//
//  ReactorsSource.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Fetches the users who reacted to a message with one emoji, a page at a time. Behind a protocol so
/// the reactors sheet's paging logic is testable without a live `FlipClient`, and so a phase-2 boost
/// amount can be layered onto the same call without touching the sheet.
public protocol ReactorsSource: Sendable {
    /// Fetches one page of reactors for `emoji` on `messageID`. `pagingToken` nil requests the first
    /// page; pass the previous page's `nextPageToken` for the next one.
    func fetchReactors(
        conversationID: ConversationID,
        messageID: MessageID,
        emoji: String,
        pagingToken: Data?
    ) async throws -> ReactorPage
}

/// The production `ReactorsSource`, over the `getReactors` RPC.
public struct FlipClientReactorsSource: ReactorsSource {
    private let client: FlipClient
    private let owner: KeyPair
    private static let pageSize = 50

    public init(client: FlipClient, owner: KeyPair) {
        self.client = client
        self.owner = owner
    }

    public func fetchReactors(
        conversationID: ConversationID,
        messageID: MessageID,
        emoji: String,
        pagingToken: Data?
    ) async throws -> ReactorPage {
        try await client.getReactors(
            owner: owner,
            conversationID: conversationID,
            messageID: messageID,
            emoji: emoji,
            pageSize: Self.pageSize,
            pagingToken: pagingToken
        )
    }
}
