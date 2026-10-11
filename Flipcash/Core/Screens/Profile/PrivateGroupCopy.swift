//
//  PrivateGroupCopy.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The words private-group screens show the requester and the host.
enum PrivateGroupCopy {

    /// "Private group · 48 members", or "Private group" before the count is known.
    static func summary(memberCount: UInt64) -> String {
        switch memberCount {
        case 0:  "Private group"
        case 1:  "Private group · 1 member"
        default: "Private group · \(memberCount) members"
        }
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

    /// The host's profile card subtitle: "1 person is waiting" or "3 people are waiting".
    static func waiting(count: Int) -> String {
        count == 1 ? "1 person is waiting" : "\(count) people are waiting"
    }

    /// The Chats tab's Join Requests row: "1 person wants to join Moony" or "3 people want to join Moony".
    static func wantToJoin(count: Int, groupName: String) -> String {
        count == 1 ? "1 person wants to join \(groupName)" : "\(count) people want to join \(groupName)"
    }

    /// The Chats tab's Join Requests row when several hosted groups have requests.
    static func wantToJoinYourGroups(count: Int) -> String {
        count == 1 ? "1 person wants to join your groups" : "\(count) people want to join your groups"
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
        }
    }
}
