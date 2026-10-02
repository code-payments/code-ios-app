//
//  ChatArchiveRules.swift
//  FlipcashCore
//

import Foundation

/// A yes/no fact the device may be unable to establish.
///
/// `unknown` is a first-class value because rule 3 treats it exactly like `no` — a mention that does
/// not resolve or a reply whose target is not stored locally stays silent — and the cross-platform
/// fixture includes those cases so both apps default the same way.
public enum ChatArchiveSignal: Equatable, Sendable {
    case yes
    case no
    case unknown
}

/// Rules 2 and 3 of the chat-archive spec, as a pure function so the cross-platform fixture can test
/// them without a simulator and the extension and the app cannot decide differently.
public enum ChatArchiveRules {

    public struct Push: Equatable, Sendable {
        public var archived: Bool
        public var muted: Bool
        public var mentionsViewer: ChatArchiveSignal
        public var repliesToViewer: ChatArchiveSignal

        public init(
            archived: Bool,
            muted: Bool,
            mentionsViewer: ChatArchiveSignal,
            repliesToViewer: ChatArchiveSignal
        ) {
            self.archived = archived
            self.muted = muted
            self.mentionsViewer = mentionsViewer
            self.repliesToViewer = repliesToViewer
        }
    }

    public struct Outcome: Equatable, Sendable {
        /// Whether the message may interrupt. On iOS the extension cannot drop a notification, so
        /// `false` is delivered `.passive` with no sound; the foreground path suppresses outright.
        public let notify: Bool
        /// Echoes the input: the chat stays archived whatever the message was (rules 2, 3 and 4).
        public let archived: Bool
    }

    /// - Muted wins over everything, including an @mention (rule 2): archiving must not add a way
    ///   through mute.
    /// - Archived but not muted notifies only for a message that @mentions the viewer or replies to
    ///   one of the viewer's messages (rule 3). Cash does not break through on its own, which is why
    ///   the message kind is not an input. `unknown` counts as `no`.
    /// - Anything else notifies, as before archive existed.
    public static func decide(_ push: Push) -> Outcome {
        if push.muted {
            return Outcome(notify: false, archived: push.archived)
        }
        guard push.archived else {
            return Outcome(notify: true, archived: false)
        }
        let addressed = push.mentionsViewer == .yes || push.repliesToViewer == .yes
        return Outcome(notify: addressed, archived: true)
    }
}
