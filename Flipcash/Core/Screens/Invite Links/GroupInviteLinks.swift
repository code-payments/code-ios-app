//
//  GroupInviteLinks.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.group-invite-links")

/// One private group's invite links as its host sees them: the list Manage Invites shows, the
/// current link the invite sheet shares, and making and revoking links.
///
/// Links and secrets live only in memory. Nothing here logs a link, a secret or a token: the link
/// carries the secret in its fragment, and the secret plus the server's records open the chat key.
@MainActor
@Observable
final class GroupInviteLinks {

    /// Reads, makes and revokes invites on the server, with the crypto they need.
    struct Service {
        typealias List = @MainActor @Sendable (ConversationID) async throws -> [Invite]
        typealias Create = @MainActor @Sendable (ConversationID, _ secret: Data, _ maxUses: UInt32, _ expiresAt: Date?) async throws -> Invite
        typealias Revoke = @MainActor @Sendable (ConversationID, InviteID) async throws -> Void
        typealias Secret = @MainActor @Sendable (Invite) -> Data?
        typealias Link = @MainActor @Sendable (_ secret: Data) -> URL?
        typealias NewSecret = @MainActor @Sendable () -> Data

        let selfUserID: UserID
        let list: List
        let create: Create
        let revoke: Revoke
        let secret: Secret
        let link: Link
        let newSecret: NewSecret
    }

    /// An invite with the link this device can rebuild for it.
    struct Entry: Identifiable, Hashable {
        let invite: Invite
        /// `nil` when the invite's secret envelope doesn't open on this device ("Can't share from
        /// this device"), or the viewer didn't make it.
        let url: URL?

        var id: InviteID { invite.id }
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    /// How long a new link lasts (frame 2d, Decision 11).
    enum Expiry: CaseIterable, Hashable {
        case oneDay
        case sevenDays
        case thirtyDays
        case never

        var title: String {
            switch self {
            case .oneDay:     "1 day"
            case .sevenDays:  "7 days"
            case .thirtyDays: "30 days"
            case .never:      "Never"
            }
        }

        func expiresAt(from now: Date) -> Date? {
            switch self {
            case .oneDay:     now.addingTimeInterval(1 * 86_400)
            case .sevenDays:  now.addingTimeInterval(7 * 86_400)
            case .thirtyDays: now.addingTimeInterval(30 * 86_400)
            case .never:      nil
            }
        }
    }

    /// How many people a new link admits (frame 2d).
    /// The 2d use limits, in the spec's order (Uses: 1, 5, 10, 25, No limit).
    enum UseLimit: CaseIterable, Hashable {
        case one
        case five
        case ten
        case twentyFive
        case unlimited

        var title: String {
            switch self {
            case .one:        "1"
            case .five:       "5"
            case .ten:        "10"
            case .twentyFive: "25"
            case .unlimited:  "No limit"
            }
        }

        var maxUses: UInt32 {
            switch self {
            case .one:        1
            case .five:       5
            case .ten:        10
            case .twentyFive: 25
            case .unlimited:  0
            }
        }
    }

    /// The server returned an invite that doesn't admit anyone, or the link couldn't be built.
    struct CreatedUnusable: Error {}

    /// How long an inactive invite stays listed (Decision 11).
    static let inactiveRetention: TimeInterval = 30 * 86_400

    let conversationID: ConversationID

    /// Every invite the server lists, newest first.
    private(set) var entries: [Entry] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isCreating = false
    private(set) var revoking: Set<InviteID> = []

    /// The secret of the create in flight or last failed, reused on retry so a retried
    /// `CreateInvite` carries the same token, on which the server is idempotent.
    @ObservationIgnored private var pendingSecret: Data?
    /// The load in flight, which a second caller joins.
    @ObservationIgnored private var loading: Task<Void, Error>?
    @ObservationIgnored private let service: Service
    @ObservationIgnored private let now: () -> Date

    init(conversationID: ConversationID, service: Service, now: @escaping () -> Date = { .now }) {
        self.conversationID = conversationID
        self.service = service
        self.now = now
    }

    // MARK: - Sections -

    var active: [Entry] {
        entries.filter { $0.invite.status == .active }
    }

    /// Exhausted, expired and revoked invites, less those more than 30 days past their end.
    var inactive: [Entry] {
        let cutoff = now().addingTimeInterval(-Self.inactiveRetention)
        return entries.filter { entry in
            guard entry.invite.status != .active else { return false }
            return (Self.endDate(of: entry.invite) ?? .distantPast) >= cutoff
        }
    }

    /// The link the invite sheet shares: the newest active invite the viewer made whose secret
    /// opens here.
    var current: Entry? {
        entries.first { entry in
            entry.invite.status == .active
                && entry.invite.createdBy == service.selfUserID
                && entry.url != nil
        }
    }

    /// When an inactive invite stopped admitting people, as far as the client can tell: its
    /// expiry for an expired one, else when it was made. The proto carries no revoke time.
    static func endDate(of invite: Invite) -> Date? {
        switch invite.status {
        case .expired:
            invite.expiresAt ?? invite.createdAt
        case .unknown, .active, .exhausted, .revoked:
            invite.createdAt
        }
    }

    // MARK: - Load -

    /// Reads every invite, newest first. Throws the server's error so a screen can tell `DENIED`.
    ///
    /// A call while a load is in flight waits for that load rather than starting a second one.
    func load() async throws {
        if let loading {
            return try await loading.value
        }
        let task = Task { try await performLoad() }
        loading = task
        defer { loading = nil }
        try await task.value
    }

    private func performLoad() async throws {
        loadState = .loading
        do {
            let invites = try await service.list(conversationID)
            entries = invites
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                .map(entry(for:))
            loadState = .loaded
        } catch {
            loadState = .failed
            throw error
        }
    }

    // MARK: - Current link -

    /// The current link, making one (7 days, no use limit) when there is no active one. A first
    /// load runs here if the sheet's own load hasn't finished or failed.
    func currentLink() async throws -> URL {
        if loadState != .loaded {
            try await load()
        }
        if let url = current?.url {
            return url
        }
        let entry: Entry
        do {
            entry = try await create(expiry: .sevenDays, limit: .unlimited)
        } catch is CreatedUnusable {
            // Only a retry can come back non-ACTIVE; that secret is spent, so start over once.
            entry = try await create(expiry: .sevenDays, limit: .unlimited)
        }
        guard let url = entry.url else { throw CreatedUnusable() }
        return url
    }

    // MARK: - Create -

    /// Makes an invite, which becomes ``current``. Throws ``ErrorCreateInvite`` from the server.
    @discardableResult
    func create(expiry: Expiry, limit: UseLimit) async throws -> Entry {
        isCreating = true
        defer { isCreating = false }

        let secret = pendingSecret ?? service.newSecret()
        pendingSecret = secret

        let invite: Invite
        do {
            invite = try await service.create(conversationID, secret, limit.maxUses, expiry.expiresAt(from: now()))
        } catch let error as ErrorCreateInvite {
            // Only a transport failure is worth retrying with the same token; any answer from the
            // server is final for this secret.
            if error != .transportFailure { pendingSecret = nil }
            throw error
        }
        pendingSecret = nil

        guard invite.status == .active, let url = service.link(secret) else {
            logger.warning("CreateInvite returned an unusable invite", metadata: [
                "status": "\(invite.status)",
            ])
            throw CreatedUnusable()
        }

        let entry = Entry(invite: invite, url: url)
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        return entry
    }

    // MARK: - Revoke -

    /// Revokes an invite. The server answers OK for one already revoked, so a retry is safe.
    func revoke(_ entry: Entry) async throws {
        guard !revoking.contains(entry.id) else { return }
        revoking.insert(entry.id)
        defer { revoking.remove(entry.id) }

        try await service.revoke(conversationID, entry.id)
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let old = entries[index].invite
        entries[index] = Entry(
            invite: Invite(
                id: old.id,
                conversationID: old.conversationID,
                createdBy: old.createdBy,
                maxUses: old.maxUses,
                useCount: old.useCount,
                createdAt: old.createdAt,
                expiresAt: old.expiresAt,
                status: .revoked,
                secretEnvelope: old.secretEnvelope
            ),
            url: nil
        )
    }

    // MARK: - Private -

    private func entry(for invite: Invite) -> Entry {
        // Only the creator's own envelope opens with this owner key.
        guard invite.createdBy == service.selfUserID, let secret = service.secret(invite) else {
            return Entry(invite: invite, url: nil)
        }
        return Entry(invite: invite, url: service.link(secret))
    }
}
