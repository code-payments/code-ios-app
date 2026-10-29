//
//  ConversationRules.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// Summary of a chat's roster — its member list — without containing it: what
/// a client needs to know whether its copy of ``Conversation/members`` is
/// stale, without holding the full list. See `chat.v1.RosterSummary`.
public struct ConversationRosterSummary: Hashable, Sendable {

    /// True number of currently joined members. ``Conversation/members`` is
    /// only a subset for a large group chat; this is its real size.
    public let memberCount: UInt64

    /// Opaque version, advanced by exactly one on every change to the
    /// membership records (a join, a leave, or a future per-member change
    /// such as a role) and never on an idempotent no-op or a profile change.
    ///
    /// Compare against the last value seen: a different value means the
    /// cached member list may be stale and should be refetched. On a stream,
    /// apply a greater value and drop the rest — delivery order does not
    /// matter. There is no delta to fetch against it, only a refetch of the
    /// members.
    public let version: UInt64

    public init(memberCount: UInt64, version: UInt64) {
        self.memberCount = memberCount
        self.version = version
    }
}

extension ConversationRosterSummary {
    public init(_ proto: Flipcash_Chat_V1_RosterSummary) {
        self.init(memberCount: proto.memberCount, version: proto.version)
    }
}

/// The signed-in user's per-viewer state for a chat — currently just mute status. See
/// `chat.v1.ViewerState`.
public struct ConversationViewerState: Hashable, Codable, Sendable {

    /// Present iff the chat is muted for the viewer. Muted pushes are still delivered (so the
    /// client can store the message) but flagged for the client to suppress the notification.
    public let mute: ConversationMuteState?

    /// Whether the viewer may call `Chat.EditChat` on this chat. `false` for every DM and for a
    /// group member the server does not permit to edit it.
    ///
    /// Server-computed from the viewer's standing and the chat's rules and never derivable
    /// client-side: show an edit affordance if and only if this is `true`. Defaults to `false`, so
    /// an unset permission always means not permitted.
    public let canEdit: Bool

    /// Opaque version, advanced by exactly one on every real change. Compared like
    /// ``ConversationRosterSummary/version``: apply the greater value and drop the rest — delivery
    /// order does not matter, and there is no delta to fetch, only a refetch.
    public let version: UInt64

    /// Present iff the creator has silenced the viewer in this chat: they may read, react and vote
    /// but not speak, so the composer is hidden while ``isSilenced(at:)`` holds. A ban is not
    /// carried here — a banned user is no longer a member and is shown no viewer state.
    public let silence: ConversationSilenceState?

    /// Whether the viewer may silence other members. Server-computed; never derive it client-side.
    public let canSilence: Bool

    /// Whether the viewer may ban other members. Server-computed; never derive it client-side.
    public let canBan: Bool

    /// Whether the viewer may create invites to this chat. Server-computed; never derive it client-side.
    public let canInvite: Bool

    /// Whether the viewer may pin and unpin messages in this chat. Server-computed; never derive it
    /// client-side. Defaults to `false`, so an unset permission always means not permitted.
    public let canPin: Bool

    public init(mute: ConversationMuteState? = nil, canEdit: Bool = false, version: UInt64 = 0, silence: ConversationSilenceState? = nil, canSilence: Bool = false, canBan: Bool = false, canInvite: Bool = false, canPin: Bool = false) {
        self.mute = mute
        self.canEdit = canEdit
        self.version = version
        self.silence = silence
        self.canSilence = canSilence
        self.canBan = canBan
        self.canInvite = canInvite
        self.canPin = canPin
    }

    private enum CodingKeys: String, CodingKey {
        case mute, canEdit, version, silence, canSilence, canBan
    }

    /// Reads a row stored before a field existed. The synthesized decoder throws on a missing key,
    /// and the store reads that as "no viewer state", which would drop the saved mute along with
    /// the new permission. A missing permission is `false`, the same as an unset one on the wire.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mute: try container.decodeIfPresent(ConversationMuteState.self, forKey: .mute),
            canEdit: try container.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false,
            version: try container.decodeIfPresent(UInt64.self, forKey: .version) ?? 0,
            silence: try container.decodeIfPresent(ConversationSilenceState.self, forKey: .silence),
            canSilence: try container.decodeIfPresent(Bool.self, forKey: .canSilence) ?? false,
            canBan: try container.decodeIfPresent(Bool.self, forKey: .canBan) ?? false
        )
    }
}

extension ConversationViewerState {
    public init(_ proto: Flipcash_Chat_V1_ViewerState) {
        self.init(
            mute: (proto.hasSettings && proto.settings.hasMute) ? ConversationMuteState(proto.settings.mute) : nil,
            canEdit: proto.hasPermissions ? proto.permissions.canEdit : false,
            version: proto.version,
            silence: (proto.hasRestrictions && proto.restrictions.hasSilence) ? ConversationSilenceState(proto.restrictions.silence) : nil,
            canSilence: (proto.hasPermissions && proto.permissions.hasModeration) ? proto.permissions.moderation.canSilence : false,
            canBan: (proto.hasPermissions && proto.permissions.hasModeration) ? proto.permissions.moderation.canBan : false,
            canInvite: proto.hasPermissions ? proto.permissions.canInvite : false,
            canPin: proto.hasPermissions ? proto.permissions.canPin : false
        )
    }
}

extension ConversationViewerState {
    /// Whether the viewer has this chat muted as of `date`.
    ///
    /// Computed on every read rather than stored: a timed mute lapses with no server signal, so a
    /// cached boolean would keep a chat silent after its mute expired.
    public func isMuted(at date: Date = .now) -> Bool {
        mute?.isActive(at: date) ?? false
    }

    /// Whether the viewer is silenced in this chat as of `date`. Computed on every read for the same
    /// reason as ``isMuted(at:)``: a timed silence lapses with no server signal.
    public func isSilenced(at date: Date = .now) -> Bool {
        silence?.isActive(at: date) ?? false
    }
}

extension Conversation {
    /// Whether the signed-in viewer may edit this chat's title or picture — the one gate an edit
    /// affordance may turn on.
    ///
    /// Forwards ``ConversationViewerState/canEdit`` and nothing else. Membership, creator identity
    /// and chat kind are deliberately *not* consulted: the server computes this from the viewer's
    /// standing against the chat's rules, and any client-side conjunct would either grant an
    /// affordance the server will deny or hide one it would have allowed. Absent viewer state means
    /// not permitted.
    public var canEdit: Bool {
        viewerState?.canEdit ?? false
    }

    /// Whether the signed-in viewer may make invite links for this group, from
    /// ``ConversationViewerState/canInvite`` alone, as ``canEdit`` is.
    public var canInvite: Bool {
        viewerState?.canInvite ?? false
    }
}

/// Whether, and until when, the signed-in user has muted a chat. See `chat.v1.MuteState`.
public enum ConversationMuteState: Hashable, Codable, Sendable {
    /// Muted until this date, after which the mute lapses client-side. Nothing is sent when it
    /// does, so the client owns the countdown.
    case until(Date)
    /// Muted forever, until explicitly unmuted.
    case forever
}

extension ConversationMuteState {
    /// Falls back to `.forever` when `duration` is unset — defensive only: the server never sends
    /// a `MuteState` without one, since its presence on `Settings.mute` is itself the mute signal.
    init(_ proto: Flipcash_Chat_V1_MuteState) {
        switch proto.duration {
        case .until(let timestamp):
            self = .until(timestamp.date)
        case .forever, nil:
            self = .forever
        }
    }

    /// Whether the mute is still in force as of `date`. A ``until(_:)`` mute in the past has
    /// lapsed; the server sends nothing when it does, so the client owns the comparison.
    public func isActive(at date: Date = .now) -> Bool {
        switch self {
        case .until(let expiry):
            return expiry > date
        case .forever:
            return true
        }
    }

    /// Builds the wire form for `MuteChatRequest.mute`.
    var proto: Flipcash_Chat_V1_MuteState {
        .with {
            switch self {
            case .until(let date):
                $0.until = .init(date: date)
            case .forever:
                $0.forever = .init()
            }
        }
    }
}

/// Whether, and until when, a member is silenced in a chat. See `chat.v1.SilenceState`.
public enum ConversationSilenceState: Hashable, Codable, Sendable {
    /// Silenced until this date, after which the silence lapses client-side. Nothing is sent when it
    /// does, so the client owns the countdown.
    case until(Date)
    /// Silenced until explicitly unsilenced.
    case forever
}

extension ConversationSilenceState {
    /// Falls back to `.forever` when `duration` is unset: a `SilenceState` is only sent while one is
    /// in force, so an unreadable duration is safer treated as silenced.
    init(_ proto: Flipcash_Chat_V1_SilenceState) {
        switch proto.duration {
        case .until(let timestamp):
            self = .until(timestamp.date)
        case .forever, nil:
            self = .forever
        }
    }

    /// Whether the silence is still in force as of `date`.
    public func isActive(at date: Date = .now) -> Bool {
        switch self {
        case .until(let expiry): expiry > date
        case .forever:           true
        }
    }

    /// Builds the wire form for `SilenceUserRequest.silence`.
    var proto: Flipcash_Chat_V1_SilenceState {
        .with {
            switch self {
            case .until(let date):
                $0.until = .init(date: date)
            case .forever:
                $0.forever = .init()
            }
        }
    }
}

/// A member the chat's creator has silenced or banned. See `chat.v1.RestrictedUser`.
public struct ConversationRestrictedUser: Hashable, Sendable, Identifiable {
    public let userID: UserID?
    public let displayName: String
    public let username: Username?
    public let profilePicture: ProfilePicture?
    /// Present iff the user is silenced.
    public let silence: ConversationSilenceState?
    /// Present iff the user is banned.
    public let bannedAt: Date?

    public var id: String { userID?.uuidString ?? displayName }

    public init(userID: UserID?, displayName: String, username: Username? = nil, profilePicture: ProfilePicture? = nil, silence: ConversationSilenceState? = nil, bannedAt: Date? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.username = username
        self.profilePicture = profilePicture
        self.silence = silence
        self.bannedAt = bannedAt
    }
}

extension ConversationRestrictedUser {
    init(_ proto: Flipcash_Chat_V1_RestrictedUser) {
        self.init(
            userID: proto.hasUserID ? try? UUID(data: proto.userID.value) : nil,
            displayName: proto.userProfile.displayName,
            username: proto.userProfile.hasUsername ? Username(proto.userProfile.username) : nil,
            profilePicture: proto.userProfile.hasProfilePicture ? ProfilePicture(proto.userProfile.profilePicture) : nil,
            silence: proto.hasSilence ? ConversationSilenceState(proto.silence) : nil,
            bannedAt: proto.hasBan && proto.ban.hasBannedAt ? proto.ban.bannedAt.date : nil
        )
    }
}

/// Requirements a user must satisfy to participate in a group chat. Only
/// ever set for group chats; unset means the chat has no participation
/// requirements. See `chat.v1.Rules`.
public struct ConversationRules: Hashable, Codable, Sendable {

    /// Requirements to read and join the chat. Empty means anyone can.
    public var listener: [ConversationListenerRule]

    /// Requirements to send messages in the chat, applied in addition to
    /// ``listener`` — a user must be able to listen before they can speak.
    /// Empty means any member can send.
    public var speaker: [ConversationSpeakerRule]

    /// The rules exactly as the server last sent them, serialized, so ``ConversationRulesEdit`` can
    /// send back the rules this client can't read. Nil for rules built locally. Left out of
    /// equality: two rule sets that read the same are the same rules.
    let wire: Data?

    public init(listener: [ConversationListenerRule] = [], speaker: [ConversationSpeakerRule] = []) {
        self.listener = listener
        self.speaker = speaker
        self.wire = nil
    }

    public static func == (lhs: ConversationRules, rhs: ConversationRules) -> Bool {
        lhs.listener == rhs.listener && lhs.speaker == rhs.speaker
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(listener)
        hasher.combine(speaker)
    }
}

extension ConversationRules {
    public init(_ proto: Flipcash_Chat_V1_Rules) {
        self.listener = proto.listener.compactMap(ConversationListenerRule.init)
        self.speaker = proto.speaker.map(ConversationSpeakerRule.init)
        self.wire = try? proto.serializedData()
    }

    /// Whether decoding dropped a listener rule this client can't read, such as a minimum balance
    /// in a currency it doesn't recognize. Such a set reads as more open than the chat is.
    public var dropsListenerRule: Bool {
        guard let wire, let proto = try? Flipcash_Chat_V1_Rules(serializedBytes: wire) else { return false }
        return proto.listener.count != listener.count
    }

    /// The server's form of these rules: what it last sent when there is one, else the rules as built.
    var wireProto: Flipcash_Chat_V1_Rules {
        guard let wire, let proto = try? Flipcash_Chat_V1_Rules(serializedBytes: wire) else { return self.proto }
        return proto
    }
}

extension ConversationRules {
    /// Builds the wire form for `StartChatRequest.GroupChatParameters.rules`.
    var proto: Flipcash_Chat_V1_Rules {
        .with {
            $0.listener = listener.map(\.proto)
            $0.speaker = speaker.map(\.proto)
        }
    }
}

/// A single requirement gating reading and joining a chat. See
/// `chat.v1.ListenerRules`.
public enum ConversationListenerRule: Hashable, Codable, Sendable {
    case minimumBalance(MinimumBalanceRequirement)
    case staff
}

extension ConversationListenerRule {
    /// Returns nil when `proto` carries neither arm of the `kind` oneof, or a
    /// `minimumBalance` requirement in a currency this client doesn't
    /// recognize.
    init?(_ proto: Flipcash_Chat_V1_ListenerRules) {
        switch proto.kind {
        case .minimumBalance(let requirement):
            guard let requirement = MinimumBalanceRequirement(requirement) else { return nil }
            self = .minimumBalance(requirement)
        case .staff:
            self = .staff
        case nil:
            return nil
        }
    }
}

extension ConversationListenerRule {
    var proto: Flipcash_Chat_V1_ListenerRules {
        .with {
            switch self {
            case .minimumBalance(let requirement):
                $0.minimumBalance = requirement.proto
            case .staff:
                $0.staff = .init()
            }
        }
    }
}

/// A single requirement gating sending messages in a chat. See
/// `chat.v1.SpeakerRules`.
public enum ConversationSpeakerRule: Hashable, Codable, Sendable {
    case minimumBalance(MinimumBalanceRequirement)
    case staff
    /// Nobody can send messages; the chat is read-only for everyone.
    case never
    /// Only the chat's creator can send messages; see `chat.v1.CreatorRequirement`.
    case creator
    /// A rule this client can't read: the `kind` oneof is unset, or names a case from a newer
    /// contract. Kept rather than dropped because a dropped rule reads as "no rule" and opens the
    /// composer; it is unsatisfied for everyone, staff included. Never sent to the server.
    case unsupported
}

extension ConversationSpeakerRule {
    /// Never fails: an unset `kind` (what a case added by a newer contract decodes to) and a
    /// `minimumBalance` in a currency this client doesn't recognize both become ``unsupported``,
    /// which keeps the composer closed instead of reading as "no rule".
    init(_ proto: Flipcash_Chat_V1_SpeakerRules) {
        switch proto.kind {
        case .minimumBalance(let requirement):
            guard let requirement = MinimumBalanceRequirement(requirement) else {
                self = .unsupported
                return
            }
            self = .minimumBalance(requirement)
        case .staff:
            self = .staff
        case .never:
            self = .never
        case .creator:
            self = .creator
        case nil:
            self = .unsupported
        }
    }
}

extension ConversationSpeakerRule {
    /// Encoding ``unsupported`` is a programmer error: it only ever comes from decoding, and there
    /// is no wire form for a rule this client can't name. The outbound path (`startChat`) builds
    /// rules from the picker, which can't produce one, so this traps in debug and, in release, yields
    /// an empty `SpeakerRules` rather than a wrong rule.
    var proto: Flipcash_Chat_V1_SpeakerRules {
        .with {
            switch self {
            case .minimumBalance(let requirement):
                $0.minimumBalance = requirement.proto
            case .staff:
                $0.staff = .init()
            case .never:
                $0.never = .init()
            case .creator:
                $0.creator = .init()
            case .unsupported:
                assertionFailure("ConversationSpeakerRule.unsupported has no wire form")
            }
        }
    }
}

/// Requires holding a minimum balance, denominated in fiat, in an acceptable
/// mint. See `chat.v1.MinimumBalanceRequirement`.
public struct MinimumBalanceRequirement: Hashable, Codable, Sendable {

    /// The minimum balance, denominated in fiat.
    public let amount: FiatAmount

    /// The mints the balance may be held in. Empty means the requirement
    /// applies across all mints; otherwise it applies only to the one listed
    /// mint. Repeated so multiple mints can be specified in the future.
    public let mints: [PublicKey]

    public init(amount: FiatAmount, mints: [PublicKey] = []) {
        self.amount = amount
        self.mints = mints
    }
}

extension MinimumBalanceRequirement {
    /// Returns nil for a currency code this client doesn't recognize.
    /// Malformed mint entries are dropped individually rather than failing
    /// the whole requirement.
    init?(_ proto: Flipcash_Chat_V1_MinimumBalanceRequirement) {
        guard let currency = CurrencyCode(rawValue: proto.amount.currency.lowercased()) else {
            return nil
        }
        self.init(
            amount: FiatAmount(value: Decimal(proto.amount.nativeAmount), currency: currency),
            mints: proto.mints.compactMap { try? PublicKey($0.value) }
        )
    }
}

extension MinimumBalanceRequirement {
    var proto: Flipcash_Chat_V1_MinimumBalanceRequirement {
        .with {
            $0.amount = .with {
                $0.currency = amount.currency.rawValue
                $0.nativeAmount = amount.doubleValue
            }
            $0.mints = mints.map { mint in .with { $0.value = mint.data } }
        }
    }
}

/// A replacement rule set for `EditChatRequest.rules`, built from the rules the server last sent
/// rather than from the decoded ``ConversationRules``, so rules this client can't read go back as the
/// group carries them.
///
/// Only the edits the server accepts can be expressed: the listener minimum balance's amount, and
/// adding, changing or removing a speaker minimum balance in the listener's currency and mints.
public struct ConversationRulesEdit: Equatable, Sendable {

    let proto: Flipcash_Chat_V1_Rules

    /// Returns nil when `rules` has no listener minimum balance to edit, or when an amount isn't in
    /// that requirement's currency.
    ///
    /// - Parameters:
    ///   - rules: the chat's current rules.
    ///   - listener: the new listener minimum, in the listener requirement's currency.
    ///   - speaker: the new speaker minimum in that currency, or nil for no speaker minimum.
    public init?(editing rules: ConversationRules, listener: FiatAmount, speaker: FiatAmount?) {
        var proto = rules.wireProto
        guard let index = proto.listener.firstIndex(where: {
            guard case .minimumBalance = $0.kind else { return false }
            return true
        }), case .minimumBalance(let current)? = proto.listener[index].kind else { return nil }

        let currency = current.amount.currency
        guard currency.lowercased() == listener.currency.rawValue,
              speaker.map({ $0.currency == listener.currency }) ?? true else { return nil }

        proto.listener[index].minimumBalance.amount.nativeAmount = listener.doubleValue

        // The listener's mints are copied as sent, not as decoded, which drops a malformed one.
        let speakerRule = speaker.map { amount in
            Flipcash_Chat_V1_SpeakerRules.with {
                $0.minimumBalance = .with {
                    $0.amount = .with {
                        $0.currency = currency
                        $0.nativeAmount = amount.doubleValue
                    }
                    $0.mints = current.mints
                }
            }
        }
        let speakerIndex = proto.speaker.firstIndex {
            guard case .minimumBalance = $0.kind else { return false }
            return true
        }
        switch (speakerIndex, speakerRule) {
        case (let index?, let rule?): proto.speaker[index] = rule
        case (let index?, nil):       proto.speaker.remove(at: index)
        case (nil, let rule?):        proto.speaker.append(rule)
        case (nil, nil):              break
        }

        self.proto = proto
    }

    /// The edited rules as this client reads them.
    public var rules: ConversationRules {
        ConversationRules(proto)
    }
}
