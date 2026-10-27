//
//  PrivateGroupCopy.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The words private-group screens show the requester and the host.
enum PrivateGroupCopy {

    /// The leave dialog's body: a private group can only be rejoined through the host's approval.
    static func leaveSubtitle(isPrivate: Bool) -> String {
        isPrivate
            ? "You\u{2019}ll lose access to the conversation. To rejoin, you\u{2019}ll need to request again and wait for the host to approve"
            : "You won't receive messages from this group any more. You can join again with an invite link"
    }

    /// "Private group · 48 members", or "Private group" before the count is known.
    static func summary(memberCount: UInt64) -> String {
        switch memberCount {
        case 0:  "Private group"
        case 1:  "Private group · 1 member"
        default: "Private group · \(memberCount) members"
        }
    }

    /// The member list's header: "1 member" or "48 members".
    static func memberCount(_ count: UInt64) -> String {
        count == 1 ? "1 member" : "\(count) members"
    }

    /// The disabled button's title while a request waits: "Request Sent" for its first minute,
    /// then its age, "Requested 10m ago", "Requested 2h ago" or "Requested 3d ago".
    static func pendingTitle(requestedAt: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(requestedAt) / 60)
        switch minutes {
        case ..<1:           return "Request Sent"
        case ..<60:          return "Requested \(minutes)m ago"
        case ..<(60 * 24):   return "Requested \(minutes / 60)h ago"
        default:             return "Requested \(minutes / (60 * 24))d ago"
        }
    }

    /// The line over the pending button, naming the host once their name is known.
    static func awaitingApproval(hostName: String?) -> String {
        if let hostName, !hostName.isEmpty {
            "You'll be able to open the chat once \(hostName) approves"
        } else {
            "You'll be able to open the chat once the host approves"
        }
    }

    /// A join request's age on the host's list: "requested just now", then "requested 10m ago",
    /// "requested 2h ago" or "requested 3d ago".
    static func requestAge(requestedAt: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(requestedAt) / 60)
        switch minutes {
        case ..<1:           return "requested just now"
        case ..<60:          return "requested \(minutes)m ago"
        case ..<(60 * 24):   return "requested \(minutes / 60)h ago"
        default:             return "requested \(minutes / (60 * 24))d ago"
        }
    }

    /// A member's row on a private group's member list: "Joined just now", then "Joined 10m ago",
    /// "Joined 2h ago" or "Joined 3d ago".
    static func joinedAge(joinedAt: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(joinedAt) / 60)
        switch minutes {
        case ..<1:           return "Joined just now"
        case ..<60:          return "Joined \(minutes)m ago"
        case ..<(60 * 24):   return "Joined \(minutes / 60)h ago"
        default:             return "Joined \(minutes / (60 * 24))d ago"
        }
    }

    /// The host's profile card subtitle: "1 person is waiting" or "3 people are waiting".
    static func waiting(count: Int) -> String {
        count == 1 ? "1 person is waiting" : "\(count) people are waiting"
    }

    /// The in-chat anchor's title: "Jasper Wants To Join" for one request, "3 People Want To Join" for several.
    static func anchorTitle(names: [String]) -> String {
        names.count == 1 ? "\(names[0]) Wants To Join" : "\(names.count) People Want To Join"
    }

    /// The in-chat anchor's names line: "Jasper and Tam", or "Jasper, Vincent and Tam" for three or more.
    static func anchorNames(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// The Join Requests empty state's body.
    static func noRequests(groupName: String) -> String {
        "When someone asks to join \(groupName), they'll show up here"
    }

    /// The sheet title when a request can't be made.
    static func unavailableTitle(groupName: String) -> String {
        "\(groupName) isn't taking requests right now"
    }
}

extension LobbyRequests.RequestError {

    /// The sheet body explaining why the request couldn't be made.
    var explanation: String {
        switch self {
        case .lobbyFull:
            "Too many people are waiting for the host to respond. Try again later"
        case .tooManyLobbies:
            "You have too many pending requests. Cancel one to request another"
        case .banned:
            // Not shown: the banned request is worded by ``GroupModerationCopy`` with its own title.
            "The host removed you from this group"
        }
    }
}
