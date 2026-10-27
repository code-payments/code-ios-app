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
        case .userJoinedViaInvite(let joiner, _):
            // Worded as a plain join until the invite notice copy is settled with Android.
            if joiner == selfID { return "You joined the group" }
            return nameOf(joiner).map { "\($0) joined the group" } ?? fallbackText
        }
    }
}
