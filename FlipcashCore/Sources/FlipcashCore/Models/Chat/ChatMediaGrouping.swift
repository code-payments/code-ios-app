//
//  ChatMediaGrouping.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Finds the photos sent together in a chat, which the transcript draws as one card stack.
///
/// Nothing on a message says which send it came from, so the set is inferred from what a send
/// looks like on the wire: one message per photo, posted back to back, the reply on the first and
/// the caption on the last. Pinned by `chat_media_groups.json`, shared with Android.
public enum ChatMediaGrouping {

    /// The longest pause between two photos of one stack.
    public static let window: TimeInterval = 2.0

    /// What the rule reads of one message.
    public struct Member: Equatable, Sendable {
        /// The server-assigned message id, gapless within a chat.
        public let seq: UInt64
        public let sender: UserID?
        public let isPhoto: Bool
        public let date: Date
        public let hasCaption: Bool
        public let isReply: Bool

        public init(seq: UInt64, sender: UserID?, isPhoto: Bool, date: Date, hasCaption: Bool, isReply: Bool) {
            self.seq = seq
            self.sender = sender
            self.isPhoto = isPhoto
            self.date = date
            self.hasCaption = hasCaption
            self.isReply = isReply
        }
    }

    /// The index ranges into `members`, which are in seq order, that draw as a stack: each a maximal
    /// run of two or more photos from one sender with consecutive seqs, each within ``window`` of
    /// the one before, where only the first may be a reply and only the last may have a caption.
    /// Grouped greedily from the oldest.
    public static func stacks(_ members: [Member]) -> [Range<Int>] {
        var stacks: [Range<Int>] = []
        var start = 0
        while start < members.count {
            var end = start + 1
            if members[start].isPhoto, members[start].sender != nil {
                while end < members.count, joins(members[end], after: members[end - 1]) {
                    end += 1
                }
            }
            if end - start >= 2 {
                stacks.append(start..<end)
            }
            start = end
        }
        return stacks
    }

    /// The stacks in `messages`, a chat's messages in seq order, as index ranges into it. A message
    /// with no server id yet takes part in none and breaks any run around it.
    public static func stacks(in messages: [ConversationMessage]) -> [Range<Int>] {
        stacks(messages.map { message in
            Member(message) ?? Member(seq: 0, sender: nil, isPhoto: false, date: message.date, hasCaption: false, isReply: false)
        })
    }

    private static func joins(_ next: Member, after previous: Member) -> Bool {
        next.isPhoto
            && next.sender == previous.sender
            && next.seq == previous.seq + 1
            && next.date.timeIntervalSince(previous.date) <= window
            && !previous.hasCaption
            && !next.isReply
    }
}

extension ChatMediaGrouping.Member {
    /// What the rule reads of a confirmed message, or nil for one with no server id yet: a pending
    /// photo keeps its own bubble, with its upload progress, until the server confirms it.
    public init?(_ message: ConversationMessage) {
        guard message.status == .sent else { return nil }
        let isPhoto: Bool
        let hasCaption: Bool
        switch message.content {
        case .media(_, let caption):
            isPhoto = true
            hasCaption = !(caption?.isEmpty ?? true)
        case .text, .cash, .deleted, .encrypted, .widget, .system:
            isPhoto = false
            hasCaption = false
        }
        self.init(
            seq: message.id.value,
            sender: message.senderID,
            isPhoto: isPhoto && !message.isDeleted,
            date: message.date,
            hasCaption: hasCaption,
            isReply: message.repliedTo != nil
        )
    }
}
