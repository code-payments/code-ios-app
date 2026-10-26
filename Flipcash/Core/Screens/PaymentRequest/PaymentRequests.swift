//
//  PaymentRequests.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.payment-requests")

/// The group payment requests read this session, merged by version.
///
/// No event carries a request change, so every copy arrives from a fetch: a chat's sections, one
/// request, or the response to the viewer's own create, close or mark-paid. Each goes through
/// ``ingest(_:)``, which keeps the greater version and, at an equal version, EXPIRED over OPEN.
@MainActor
@Observable
final class PaymentRequests {

    typealias GetChatPage = @MainActor @Sendable (ConversationID, GroupPaymentRequest.Section, Int) async throws -> [GroupPaymentRequest]
    typealias GetRequest = @MainActor @Sendable (PaymentRequestID) async throws -> (request: GroupPaymentRequest, paymentIntentID: Data?)
    typealias OpeningSeal = @MainActor @Sendable (ConversationID) async -> ChatSeal?
    typealias Create = @MainActor @Sendable (_ idempotencyKey: Data, ConversationID, GroupPaymentRequest.Split) async throws -> GroupPaymentRequest
    typealias Close = @MainActor @Sendable (PaymentRequestID) async throws -> GroupPaymentRequest
    typealias MarkPaid = @MainActor @Sendable (PaymentRequestID, UserID) async throws -> GroupPaymentRequest
    typealias GetPage = @MainActor @Sendable (ConversationID, GroupPaymentRequest.Section, _ pageSize: Int, _ pagingToken: Data?) async throws -> (requests: [GroupPaymentRequest], nextPagingToken: Data?)

    /// A mutation called on a store built without it, as tests that only read do.
    struct Unconfigured: Error {}

    /// The first page of OPEN requests a chat refetch reads.
    static let openPageSize = 100
    /// The first page of RESOLVED requests a chat refetch reads, enough to fill the deck's 24 hours.
    static let resolvedPageSize = 20
    /// How often an on-screen chat or details sheet refetches.
    static let pollInterval: Duration = .seconds(45)

    /// How long an on-screen poll waits before its `attempt`th retry of a read that left something
    /// loading: 2 s doubling, never past ``pollInterval``.
    static func retryDelay(attempt: Int) -> Duration {
        min(.seconds(2 << min(attempt, 5)), pollInterval)
    }

    private var requests: [PaymentRequestID: GroupPaymentRequest] = [:]
    /// Requests the server answered `DENIED` or `NOT_FOUND` for; their cards render as unsupported.
    private(set) var unavailable: Set<PaymentRequestID> = []
    /// Bumped on every chat refetch, so a deck can return to its default order.
    private(set) var chatRefreshes: [ConversationID: Int] = [:]

    /// Each chat's seal for opening encrypted request text, once loaded.
    private var seals: [ConversationID: ChatSeal] = [:]

    @ObservationIgnored private let getChatPage: GetChatPage
    @ObservationIgnored private let getRequest: GetRequest
    @ObservationIgnored private let openingSeal: OpeningSeal
    @ObservationIgnored private let createRequest: Create
    @ObservationIgnored private let closeRequest: Close
    @ObservationIgnored private let markPaidShare: MarkPaid
    @ObservationIgnored private let getPage: GetPage
    @ObservationIgnored private var inFlight: Set<PaymentRequestID> = []
    @ObservationIgnored private var sealReads: Set<ConversationID> = []
    /// Requests whose last read failed short of a server answer, retried on the next chat refetch.
    @ObservationIgnored private var failedReads: Set<PaymentRequestID> = []
    /// Chats whose last section read failed.
    @ObservationIgnored private var failedChats: Set<ConversationID> = []

    init(
        getChatPage: @escaping GetChatPage,
        getRequest: @escaping GetRequest,
        openingSeal: @escaping OpeningSeal = { _ in nil },
        create: @escaping Create = { _, _, _ in throw Unconfigured() },
        close: @escaping Close = { _ in throw Unconfigured() },
        markPaid: @escaping MarkPaid = { _, _ in throw Unconfigured() },
        getPage: @escaping GetPage = { _, _, _, _ in throw Unconfigured() }
    ) {
        self.getChatPage = getChatPage
        self.getRequest = getRequest
        self.openingSeal = openingSeal
        self.createRequest = create
        self.closeRequest = close
        self.markPaidShare = markPaid
        self.getPage = getPage
    }

    /// The chat's held seal, for sealing a new request's text.
    func seal(for conversationID: ConversationID) -> ChatSeal? {
        seals[conversationID]
    }

    /// Creates a request; retrying with the same `idempotencyKey` returns the same request.
    func create(idempotencyKey: Data, in conversationID: ConversationID, split: GroupPaymentRequest.Split) async throws -> GroupPaymentRequest {
        let created = try await createRequest(idempotencyKey, conversationID, split)
        ingest([created])
        return created
    }

    /// Closes `id` early. Creator only.
    func close(_ id: PaymentRequestID) async throws {
        ingest([try await closeRequest(id)])
    }

    /// Marks `userID`'s share of `id` paid outside Flipcash. Creator only.
    func markPaid(_ id: PaymentRequestID, userID: UserID) async throws {
        ingest([try await markPaidShare(id, userID)])
    }

    /// Loads `conversationID`'s opening seal if it isn't held or being read yet, so encrypted titles
    /// can open.
    func loadSeal(for conversationID: ConversationID) async {
        guard seals[conversationID] == nil, sealReads.insert(conversationID).inserted else { return }
        defer { sealReads.remove(conversationID) }
        guard let seal = await openingSeal(conversationID) else { return }
        seals[conversationID] = seal
    }

    /// `request`'s title and description as the viewer reads them, nil when they can't be read.
    func text(of request: GroupPaymentRequest) -> PaymentRequestText? {
        PaymentRequestText(request: request, seal: request.chatID.flatMap { seals[$0] })
    }

    /// How a widget for `id`, sent by `sender` in `conversationID`, draws as of `now`.
    func cardState(
        for id: PaymentRequestID,
        in conversationID: ConversationID,
        sentBy sender: UserID?,
        copy: PaymentRequestCopy,
        now: Date
    ) -> PaymentRequestCardState {
        if unavailable.contains(id) { return .unsupported }
        guard let request = requests[id] else { return .loading }
        guard request.belongs(to: conversationID, sentBy: sender) else { return .unsupported }
        if case .encrypted = request.split?.text, seals[conversationID] == nil { return .loading }
        guard let text = text(of: request) else { return .unsupported }
        return .card(ChatPaymentRequestContent.Card(request: request, title: text.title, copy: copy, now: now))
    }

    /// The stored copy of `id`, if any.
    func request(_ id: PaymentRequestID) -> GroupPaymentRequest? {
        requests[id]
    }

    /// `conversationID`'s requests the deck shows to `viewer` as of `now`, in deck order.
    func deck(for conversationID: ConversationID, viewer: UserID?, at now: Date) -> [GroupPaymentRequest] {
        GroupPaymentRequest.deckOrder(requests.values.filter { $0.chatID == conversationID }, viewer: viewer, at: now)
    }

    /// Merges fetched copies into the store.
    func ingest(_ incoming: [GroupPaymentRequest]) {
        for request in incoming {
            if let existing = requests[request.id] {
                let kept = GroupPaymentRequest.merged(existing: existing, incoming: request)
                if kept != existing { requests[request.id] = kept }
            } else {
                requests[request.id] = request
            }
            unavailable.remove(request.id)
        }
    }

    /// Reads `conversationID`'s OPEN and RESOLVED first pages, and its seal if not held yet. A failed
    /// read keeps what was held.
    func refreshChat(_ conversationID: ConversationID) async {
        async let sealed: Void = loadSeal(for: conversationID)
        do {
            async let open = getChatPage(conversationID, .open, Self.openPageSize)
            async let resolved = getChatPage(conversationID, .resolved, Self.resolvedPageSize)
            ingest(try await open + resolved)
            chatRefreshes[conversationID, default: 0] += 1
            failedChats.remove(conversationID)
        } catch {
            failedChats.insert(conversationID)
            logger.warning("Failed to read a chat's payment requests", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
        }
        await sealed
        for id in failedReads {
            await fetchIfMissing(id)
        }
    }

    /// Whether `conversationID` still has something loading that a sooner refetch could fill: a failed
    /// section or request read, or encrypted text with no seal to open it.
    func isSettling(_ conversationID: ConversationID) -> Bool {
        if failedChats.contains(conversationID) || !failedReads.isEmpty { return true }
        guard seals[conversationID] == nil else { return false }
        return requests.values.contains { $0.chatID == conversationID && $0.hasEncryptedText }
    }

    /// Whether `id` is still loading: not read yet, or its encrypted text waits on the chat's seal.
    func isSettling(request id: PaymentRequestID) -> Bool {
        if unavailable.contains(id) { return false }
        guard let request = requests[id] else { return true }
        guard request.hasEncryptedText, let chatID = request.chatID else { return false }
        return seals[chatID] == nil
    }

    /// Reads one page of a chat's `section` for Request Money history and merges it. Returns the page's
    /// request ids in server order and the token for the next page, `nil` after the last.
    func page(
        _ conversationID: ConversationID,
        section: GroupPaymentRequest.Section,
        pageSize: Int,
        after pagingToken: Data?
    ) async throws -> (ids: [PaymentRequestID], nextPagingToken: Data?) {
        let page = try await getPage(conversationID, section, pageSize, pagingToken)
        ingest(page.requests)
        return (page.requests.map(\.id), page.nextPagingToken)
    }

    /// Reads one request, and its chat's seal if not held yet, and merges it. Returns the intent id the
    /// viewer pays under, `nil` when the viewer has no unpaid share. Throws what the read threw.
    @discardableResult
    func refresh(_ id: PaymentRequestID) async throws -> Data? {
        do {
            let fetched = try await getRequest(id)
            ingest([fetched.request])
            if let chatID = fetched.request.chatID { await loadSeal(for: chatID) }
            return fetched.paymentIntentID
        } catch let error as ErrorGetPaymentRequest {
            switch error {
            case .denied, .notFound:
                unavailable.insert(id)
            case .ok, .unknown, .transportFailure, .cancelled, .rejected:
                break
            }
            throw error
        }
    }

    /// Reads `id` when it isn't stored yet and no read of it is already running.
    func fetchIfMissing(_ id: PaymentRequestID) async {
        guard requests[id] == nil, !unavailable.contains(id), inFlight.insert(id).inserted else { return }
        defer { inFlight.remove(id) }
        do {
            try await refresh(id)
            failedReads.remove(id)
        } catch {
            if unavailable.contains(id) {
                failedReads.remove(id)
            } else {
                failedReads.insert(id)
            }
            logger.warning("Failed to read a payment request", metadata: ["error": "\(error)"])
        }
    }
}

private extension GroupPaymentRequest {
    var hasEncryptedText: Bool {
        if case .encrypted = split?.text { return true }
        return false
    }
}

/// How a payment-request widget draws in the transcript.
enum PaymentRequestCardState: Hashable, Sendable {
    /// The request, or the chat's key, is still loading: the card's frame with placeholder lines.
    case loading
    case card(ChatPaymentRequestContent.Card)
    /// The chat's unsupported-message bubble, for the cases the spec lists.
    case unsupported
}

/// A payment request picked to show, as a sheet item.
struct PaymentRequestSelection: Identifiable, Hashable {
    let id: PaymentRequestID
}

/// What keys the chat's request poll: it restarts when the chat changes or the app returns to the foreground.
struct PaymentRequestPoll: Hashable {
    let conversationID: ConversationID?
    let isActive: Bool
}

/// What keys the details poll: it restarts when the request changes or the app returns to the foreground.
struct PaymentRequestDetailsPoll: Hashable {
    let requestID: PaymentRequestID
    let isActive: Bool
}
