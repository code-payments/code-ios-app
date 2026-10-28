//
//  GroupInviteLanding.swift
//  Code
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.group-invite")

/// The joiner's side of an invite link: derive the token, look the link up, read the preview
/// roster with it, and join. Mirrors Android's `GroupInviteLanding`. The secret is held by the
/// screen for its lifetime and never logged; only the chat id appears in a log line.
struct GroupInviteLanding {

    /// Why a link no longer admits anyone. Each has its own line on the dead-invite screen
    /// (node 12846:126).
    enum DeadReason: Equatable {
        case exhausted
        case expired
        case revoked
    }

    /// What opening an invite link found.
    enum Lookup {
        /// The viewer is already in the group, so the link has nothing to offer: open the chat.
        case alreadyMember(ConversationID)
        /// The group as the link shows it. `dead` is set when the link no longer admits anyone.
        case found(token: InviteToken, conversation: Conversation, dead: DeadReason?)
        /// The link matches no invite (node 12846:148).
        case notFound
        /// The host removed the viewer from this group (node 12846:160).
        case banned
        /// The lookup itself failed; nothing is known about the link.
        case failed
    }

    /// What joining through a link came to.
    enum JoinResult: Equatable {
        case joined(ConversationID)
        /// The link died between preview and join; the screen switches to the dead state in place.
        case dead(DeadReason)
        /// INVITE_NOT_FOUND: the link matches no invite.
        case notFound
        /// NOT_FOUND: the link is real but the group is gone.
        case groupGone
        case banned
        /// DENIED or RULES_NOT_SATISFIED. Neither should happen with an invite, so the screen
        /// stays on the preview with the generic alert rather than the connection one.
        case refused
        /// A transport failure: the connection alert (node 12846:220).
        case failed

        /// The alert a failed join shows, or nil when the screen changes state instead.
        /// BANNED and INVITE_NOT_FOUND pop the preview once dismissed, as the spec's JoinChat table says.
        var alert: JoinAlert? {
            switch self {
            case .banned:
                JoinAlert(title: "You Can’t Join This Group", subtitle: "The host has removed you from this group", popsPreview: true)
            case .notFound:
                JoinAlert(title: "Link Not Found", subtitle: "This invite link isn’t valid. Ask whoever sent it for a new one", popsPreview: true)
            case .refused:
                JoinAlert(title: "Couldn’t Join Group", subtitle: "Something went wrong. Please try again", popsPreview: false)
            case .failed:
                JoinAlert(title: "Couldn’t Join Group", subtitle: "Check your connection and try again", popsPreview: false)
            case .joined, .dead, .groupGone:
                nil
            }
        }
    }

    struct JoinAlert: Equatable {
        let title: String
        let subtitle: String
        let popsPreview: Bool
    }

    /// One read of the preview roster, or the news that the link stopped granting it.
    enum RosterResult {
        case page([ConversationMember], memberCount: UInt64)
        /// `GetRoster` answered DENIED: the invite is no longer valid.
        case denied
        case failed
    }

    struct Service {
        typealias GetInvite = @MainActor @Sendable (InviteToken) async throws -> (conversation: Conversation, status: Invite.Status)
        typealias GetRoster = @MainActor @Sendable (ConversationID, InviteToken) async throws -> FlipClient.RosterPage
        typealias Join = @MainActor @Sendable (ConversationID, InviteJoinParameters) async throws -> Void
        typealias IsMember = @MainActor @Sendable (ConversationID) -> Bool

        let owner: KeyPair
        let getInvite: GetInvite
        let getRoster: GetRoster
        let join: Join
        let isMember: IsMember
    }

    let service: Service

    @MainActor
    func lookup(_ secret: InviteLinkSecret) async -> Lookup {
        guard let token = try? secret.token() else { return .notFound }
        let preview: (conversation: Conversation, status: Invite.Status)
        do {
            preview = try await service.getInvite(token)
        } catch ErrorGetInvite.notFound {
            return .notFound
        } catch ErrorGetInvite.banned {
            return .banned
        } catch {
            return .failed
        }
        if service.isMember(preview.conversation.id) {
            return .alreadyMember(preview.conversation.id)
        }
        return .found(token: token, conversation: preview.conversation, dead: Self.deadReason(preview.status))
    }

    /// The invite's own token reads the roster of a group the viewer isn't in.
    @MainActor
    func roster(of conversationID: ConversationID, token: InviteToken) async -> RosterResult {
        do {
            let page = try await service.getRoster(conversationID, token)
            return .page(page.members, memberCount: page.rosterSummary.memberCount)
        } catch ErrorGetRoster.denied {
            return .denied
        } catch {
            return .failed
        }
    }

    @MainActor
    func join(_ secret: InviteLinkSecret, conversationID: ConversationID) async -> JoinResult {
        guard let parameters = try? secret.joinParameters(owner: service.owner, conversationID: conversationID) else {
            return .failed
        }
        do {
            try await service.join(conversationID, parameters)
            return .joined(conversationID)
        } catch let error as ErrorJoinChat {
            switch error {
            case .inviteExhausted: return .dead(.exhausted)
            case .inviteExpired:   return .dead(.expired)
            case .inviteRevoked:   return .dead(.revoked)
            case .inviteNotFound:  return .notFound
            case .notFound:        return .groupGone
            case .banned:          return .banned
            case .denied, .rulesNotSatisfied:
                // Points to a client bug (see `refused`). The chat id is the only identifier
                // logged, never the link or its secret.
                logger.error("JoinChat refused an invite join", metadata: [
                    "error": "\(error)",
                    "conversationID": "\(conversationID)",
                ])
                return .refused
            case .ok, .unknown, .transportFailure, .cancelled, .rejected:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    static func deadReason(_ status: Invite.Status) -> DeadReason? {
        switch status {
        case .exhausted: .exhausted
        case .expired:   .expired
        case .revoked:   .revoked
        case .active, .unknown: nil
        }
    }
}
