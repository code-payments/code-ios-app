//
//  Community.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// The community around a currency launched on Flipcash.
public struct Community: Sendable {
    public let mint: PublicKey
    public let name: String
    /// The community's leader, when the server names one and the profile parses.
    public let leader: Profile?
    /// The currency's top-holder group chats, in the server's order.
    public let topHolderChats: [Conversation]

    public init(mint: PublicKey, name: String, leader: Profile?, topHolderChats: [Conversation]) {
        self.mint = mint
        self.name = name
        self.leader = leader
        self.topHolderChats = topHolderChats
    }
}

extension Community {
    /// Builds a community from its proto, or throws when the mint does not parse.
    init(_ proto: Flipcash_Community_V1_CommunityMetadata) throws {
        self.init(
            mint: try PublicKey(proto.mint.value),
            name: proto.name,
            leader: proto.hasLeader && proto.leader.hasProfile ? try? Profile(proto.leader.profile) : nil,
            topHolderChats: proto.topHolderChats.map(Conversation.init)
        )
    }
}
