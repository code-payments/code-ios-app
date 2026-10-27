//
//  LobbyRequests.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.lobby-requests")

/// The private groups the signed-in user has asked to join and when each request was made.
///
/// The contract has no "my requests" list and no push for an outcome, so the client keeps this one
/// and checks each entry against `GetChat.in_lobby`. Owner-scoped in `UserDefaults` the way
/// `RecentReactionsStore` is.
@MainActor
@Observable
final class LobbyRequests {

    /// What asking to join a private group came to.
    enum RequestOutcome: Equatable {
        /// The user is waiting in the lobby.
        case requested
        /// The user was already a member, so there is nothing to wait for.
        case alreadyMember
    }

    /// Why a request could not be made, worded for the sheet that explains it.
    enum RequestError: Error, Equatable {
        /// The group's lobby has no room.
        case lobbyFull
        /// The user is waiting on too many groups already.
        case tooManyLobbies
        /// The host removed the user from the group and hasn't unbanned them.
        case banned
    }

    typealias EnterLobby = @MainActor @Sendable (ConversationID) async throws -> Lobby
    typealias LeaveLobby = @MainActor @Sendable (ConversationID) async throws -> Void

    private var requests: [ConversationID: Date]

    @ObservationIgnored private let enterLobby: EnterLobby
    @ObservationIgnored private let leaveLobby: LeaveLobby
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    /// Loads the owner's requests. Unreadable data is treated as none: the next refresh of a group's
    /// profile reads its `in_lobby` from the server anyway.
    init(
        defaults: UserDefaults = .standard,
        owner: PublicKey,
        enterLobby: @escaping EnterLobby,
        leaveLobby: @escaping LeaveLobby
    ) {
        self.defaults = defaults
        self.key = "flipcash-\(owner.base58)-lobby-requests"
        self.enterLobby = enterLobby
        self.leaveLobby = leaveLobby
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode([Data: Date].self, from: data) {
            self.requests = Dictionary(uniqueKeysWithValues: stored.map { (ConversationID(data: $0.key), $0.value) })
        } else {
            self.requests = [:]
        }
    }

    /// Every group with a request outstanding.
    var conversationIDs: [ConversationID] {
        Array(requests.keys)
    }

    /// When the user asked to join `conversationID`, or nil when no request is outstanding.
    func requestedAt(_ conversationID: ConversationID) -> Date? {
        requests[conversationID]
    }

    /// Enters `conversationID`'s lobby and remembers the request.
    func request(_ conversationID: ConversationID) async throws -> RequestOutcome {
        do {
            let lobby = try await enterLobby(conversationID)
            set(lobby.enteredAt ?? .now, for: conversationID)
            return .requested
        } catch ErrorEnterLobby.alreadyMember {
            set(nil, for: conversationID)
            return .alreadyMember
        } catch ErrorEnterLobby.lobbyFull {
            throw RequestError.lobbyFull
        } catch ErrorEnterLobby.tooManyLobbies {
            throw RequestError.tooManyLobbies
        } catch ErrorEnterLobby.banned {
            throw RequestError.banned
        }
    }

    /// Withdraws the request to join `conversationID`.
    func cancel(_ conversationID: ConversationID) async throws {
        try await leaveLobby(conversationID)
        set(nil, for: conversationID)
    }

    /// Settles a request against the server's copy of the group: one that no longer has the user in
    /// its lobby was admitted, denied or withdrawn elsewhere, and one made on another device starts
    /// pending here, aged from now since `GetChat` doesn't say when it was made.
    func reconcile(with conversation: Conversation, now: Date = .now) {
        switch (requests[conversation.id] != nil, conversation.inLobby) {
        case (true, false):
            set(nil, for: conversation.id)
        case (false, true):
            set(now, for: conversation.id)
        case (true, true), (false, false):
            break
        }
    }

    private func set(_ date: Date?, for conversationID: ConversationID) {
        requests[conversationID] = date
        let stored = Dictionary(uniqueKeysWithValues: requests.map { ($0.key.data, $0.value) })
        do {
            defaults.set(try JSONEncoder().encode(stored), forKey: key)
        } catch {
            logger.error("Failed to encode lobby requests", metadata: ["error": "\(error)"])
        }
    }
}
