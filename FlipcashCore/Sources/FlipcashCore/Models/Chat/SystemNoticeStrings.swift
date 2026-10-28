//
//  SystemNoticeStrings.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The words a system notice is drawn in wherever it names the users it is about: the transcript row
/// and the chat list's last-message line. The wording matches Android's.
public enum SystemNoticeStrings {

    /// The notice's text: a sentence naming the users `event` involves, or `fallbackText` when there
    /// is no event or `nameOf` cannot name a user the chosen sentence needs.
    ///
    /// The viewer reads as "You" only through their own sentences, never in a name slot, and a
    /// `nil` `selfID` means nobody is the viewer. An admitter who is also the joiner is no admitter.
    public static func text(
        for event: ConversationMessage.SystemEvent?,
        fallbackText: String,
        selfID: UserID?,
        nameOf: (UserID) -> String?
    ) -> String {
        guard let event else { return fallbackText }
        switch event {
        case .userJoined(let joiner, let admittedBy):
            let admitter = admittedBy == joiner ? nil : admittedBy
            let isViewerJoiner = joiner == selfID

            guard let admitter else {
                if isViewerJoiner { return "You joined the group" }
                return nameOf(joiner).map { "\($0) joined the group" } ?? fallbackText
            }
            if admitter == selfID {
                return nameOf(joiner).map { "You added \($0)" } ?? fallbackText
            }
            guard let admitterName = nameOf(admitter) else { return fallbackText }
            if isViewerJoiner { return "\(admitterName) added you" }
            return nameOf(joiner).map { "\(admitterName) added \($0)" } ?? fallbackText
        case .userJoinedViaInvite(let joiner, let inviter):
            // Open 3 option B (nodes 12846:374, 12846:427, 12846:480).
            if joiner == selfID {
                return nameOf(inviter).map { "You joined with \($0)’s invite link" } ?? fallbackText
            }
            guard let joinerName = nameOf(joiner) else { return fallbackText }
            if inviter == selfID { return "\(joinerName) joined with your invite link" }
            return nameOf(inviter).map { "\(joinerName) joined with \($0)’s invite link" } ?? fallbackText
        }
    }

    /// The name in `text`, the result of ``text(for:fallbackText:selfID:nameOf:)`` for `event`, that
    /// opens a profile: only the inviter of an invite join. "your" and "You" name the viewer, who
    /// has no profile to open from a notice, so those notices have none.
    public static func userLink(
        for event: ConversationMessage.SystemEvent?,
        text: String,
        selfID: UserID?,
        nameOf: (UserID) -> String?
    ) -> SystemNoticeUserLink? {
        guard case .userJoinedViaInvite(_, let inviter) = event, inviter != selfID,
              let name = nameOf(inviter) else { return nil }
        // The possessive anchors the match: the joiner's name may contain the inviter's.
        guard let found = text.range(of: "\(name)’s", options: .backwards) else { return nil }
        let nameEnd = text.index(found.lowerBound, offsetBy: name.count)
        return SystemNoticeUserLink(range: NSRange(found.lowerBound..<nameEnd, in: text), userID: inviter)
    }
}

/// A name in a system notice's text, as a UTF-16 range, that opens `userID`'s profile.
public struct SystemNoticeUserLink: Hashable, Codable, Sendable {
    public let location: Int
    public let length: Int
    public let userID: UserID

    public var range: NSRange { NSRange(location: location, length: length) }

    public init(range: NSRange, userID: UserID) {
        self.location = range.location
        self.length = range.length
        self.userID = userID
    }
}
