//
//  GroupModeration.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashUI

/// The host's moderation calls on a group: silence, unsilence, ban, unban, and the list of everyone
/// currently restricted. `FlipClient` conforms; tests supply a fake.
protocol ConversationModeration: AnyObject, Sendable {
    func silenceUser(owner: KeyPair, conversationID: ConversationID, userID: UserID, silence: ConversationSilenceState) async throws
    func unsilenceUser(owner: KeyPair, conversationID: ConversationID, userID: UserID) async throws
    func banUser(owner: KeyPair, conversationID: ConversationID, userID: UserID) async throws
    func unbanUser(owner: KeyPair, conversationID: ConversationID, userID: UserID) async throws
    func getRestrictedUsers(owner: KeyPair, conversationID: ConversationID) async throws -> [ConversationRestrictedUser]
}

extension FlipClient: ConversationModeration {}

/// How long to silence a member for. The durations match Mute Notifications, but the last one reads
/// "Forever": "Always" would name a state, and this names how long the host's action lasts.
enum SilenceDuration: CaseIterable, Hashable {
    case oneHour, eightHours, oneWeek, forever

    var title: String {
        switch self {
        case .oneHour:    "1 Hour"
        case .eightHours: "8 Hours"
        case .oneWeek:    "1 Week"
        case .forever:    "Forever"
        }
    }

    var systemSymbol: SystemSymbol {
        switch self {
        case .oneHour, .eightHours, .oneWeek: .clock
        case .forever:                        .speakerSlash
        }
    }

    /// The silence this choice applies when picked at `now`. A timed one is an instant, not a
    /// duration: the server stores the end and the client owns the countdown against it.
    func silence(from now: Date) -> ConversationSilenceState {
        switch self {
        case .oneHour:    .until(now.addingTimeInterval(60 * 60))
        case .eightHours: .until(now.addingTimeInterval(8 * 60 * 60))
        case .oneWeek:    .until(now.addingTimeInterval(7 * 24 * 60 * 60))
        case .forever:    .forever
        }
    }
}

/// Copy for the host's moderation prompts, kept apart from the views so the wording is one place.
enum GroupModerationCopy {

    static func silenceTitle(firstName: String) -> String {
        "Silence \(firstName)"
    }

    static func silenceCaption(groupName: String) -> String {
        "They can still read and react in \(groupName), but can't send messages. Only they're told"
    }

    static func removeTitle(firstName: String) -> String {
        "Remove \(firstName)?"
    }

    static func removeSubtitle(groupName: String) -> String {
        "They'll leave \(groupName) and can't rejoin until you unban them. Their messages stay in the chat"
    }

    static let bannedTitle = "You Can't Join This Group"

    static func bannedSubtitle(groupName: String) -> String {
        "The host removed you from \(groupName)"
    }

    static func silencedToast(firstName: String, duration: SilenceDuration) -> String {
        switch duration {
        case .oneHour:    "\(firstName) is silenced for 1 hour"
        case .eightHours: "\(firstName) is silenced for 8 hours"
        case .oneWeek:    "\(firstName) is silenced for 1 week"
        case .forever:    "\(firstName) is silenced"
        }
    }

    static func unsilencedToast(firstName: String) -> String {
        "\(firstName) can send messages again"
    }

    static let silenceLiftedToast = "You are now able to chat again"

    /// Whether the viewer's silence just lifted: they were under one and now are not. It is the one
    /// transition both the host's unsilence and a timed silence running out pass through, so keying on
    /// it shows the toast once per lift. Opening a chat already unsilenced has no earlier silence, and a
    /// silence replaced by another is not a lift.
    static func silenceLifted(from previous: ConversationSilenceState?, to current: ConversationSilenceState?) -> Bool {
        previous != nil && current == nil
    }

    static let noSilenced = "No one is silenced"
    static let noRemoved = "No one has been removed"
    static let noSilencedBody = "Silence a member from their profile or by pressing and holding their message. They can still read, but not send"
    static let noRemovedBody = "Members you remove from the group will show up here, where you can let them back in"

    /// The first word of a display name, which is how the host's prompts address the member.
    static func firstName(of name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

/// The host's moderation actions on one group, bound to the signed-in owner.
@MainActor
struct GroupModeration {

    let moderation: any ConversationModeration
    let owner: KeyPair
    let conversationID: ConversationID
    /// Told the toast message once a silence change has succeeded, never on a failure.
    var announce: @MainActor (String) -> Void = { _ in }

    func silence(_ userID: UserID, firstName: String, duration: SilenceDuration, now: Date = .now) async throws {
        try await moderation.silenceUser(owner: owner, conversationID: conversationID, userID: userID, silence: duration.silence(from: now))
        announce(GroupModerationCopy.silencedToast(firstName: firstName, duration: duration))
    }

    func unsilence(_ userID: UserID, firstName: String) async throws {
        try await moderation.unsilenceUser(owner: owner, conversationID: conversationID, userID: userID)
        announce(GroupModerationCopy.unsilencedToast(firstName: firstName))
    }

    /// Puts `userID` out of the group and bars them from rejoining. The roster drops them through
    /// the `MemberLeft` update the other members get, so nothing local needs to move.
    func remove(_ userID: UserID) async throws {
        try await moderation.banUser(owner: owner, conversationID: conversationID, userID: userID)
    }

    func unban(_ userID: UserID) async throws {
        try await moderation.unbanUser(owner: owner, conversationID: conversationID, userID: userID)
    }

    func restrictedUsers() async throws -> [ConversationRestrictedUser] {
        try await moderation.getRestrictedUsers(owner: owner, conversationID: conversationID)
    }
}

/// Which of the host's two lists a restricted user belongs on, and how a row reads.
enum RestrictedUserList: Hashable {
    case silenced
    case removed
}

extension ConversationRestrictedUser {

    /// Whether the user is banned, which wins the row when they are also silenced.
    var isRemoved: Bool { bannedAt != nil }

    /// Whether the silence is still in force at `date`. A timed one lapses with no event, and the
    /// index can still list it for a moment after.
    func isSilenced(at date: Date) -> Bool {
        silence?.isActive(at: date) ?? false
    }

    /// Whether this user belongs on `list` as of `date`: ban wins, so a user who is both appears
    /// only under Removed.
    func belongs(on list: RestrictedUserList, at date: Date) -> Bool {
        switch list {
        case .silenced: !isRemoved && isSilenced(at: date)
        case .removed:  isRemoved
        }
    }

    /// The second line of the user's row on `list`.
    func detail(on list: RestrictedUserList, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch list {
        case .silenced:
            switch silence {
            case .until(let end):
                return "Silenced · until \(ConversationGatePanel.endText(end, now: now, calendar: calendar, locale: locale))"
            case .forever, nil:
                return "Silenced · forever"
            }
        case .removed:
            let date = (bannedAt ?? now).formatted(Date.FormatStyle().month(.abbreviated).day().locale(locale))
            let base = "Removed \(date)"
            return isSilenced(at: now) ? "\(base) · also silenced" : base
        }
    }
}

/// One of the host's lists, loaded from a single paged read and edited locally afterward.
///
/// The server's index trails writes briefly, so a row the host just acted on is removed here rather
/// than refetched, and no read follows a write.
@MainActor
@Observable
final class RestrictedUsersModel {

    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    let list: RestrictedUserList

    private(set) var phase: Phase = .loading
    private(set) var users: [ConversationRestrictedUser] = []
    /// Rows whose action is in flight, by `ConversationRestrictedUser.id`.
    private(set) var inFlight: Set<String> = []

    @ObservationIgnored private let moderation: GroupModeration

    init(list: RestrictedUserList, moderation: GroupModeration) {
        self.list = list
        self.moderation = moderation
    }

    /// The rows to draw as of `date`.
    func rows(at date: Date) -> [ConversationRestrictedUser] {
        users.filter { $0.belongs(on: list, at: date) }
    }

    func load() async {
        do {
            users = try await moderation.restrictedUsers()
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
            ErrorReporting.captureError(error, reason: "Failed to load restricted users")
        }
    }

    /// Runs the list's undo (Unsilence or Unban) on `user` and drops the row on success. Throws so
    /// the screen can say it failed; the row stays.
    func undo(_ user: ConversationRestrictedUser) async throws {
        guard let userID = user.userID, !inFlight.contains(user.id) else { return }
        inFlight.insert(user.id)
        defer { inFlight.remove(user.id) }
        switch list {
        case .silenced: try await moderation.unsilence(userID, firstName: GroupModerationCopy.firstName(of: user.displayName))
        case .removed:  try await moderation.unban(userID)
        }
        users.removeAll { $0.id == user.id }
    }
}
