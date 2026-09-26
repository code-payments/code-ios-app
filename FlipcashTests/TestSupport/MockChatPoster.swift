//
//  MockChatPoster.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash
import FlipcashCore

/// Records every post and answers with `accepts`.
@MainActor
final class MockChatPoster: ChatMessagePosting {

    struct Post: Equatable {
        let text: String
        let conversationID: ConversationID
    }

    var accepts = true

    private(set) var posts: [Post] = []

    func postOnce(_ text: String, to conversationID: ConversationID) async -> Bool {
        posts.append(Post(text: text, conversationID: conversationID))
        return accepts
    }
}
