//
//  ChatItem+RequestEvents.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// A stored payment request a transcript row can name: the request and its title as the viewer
/// reads it.
nonisolated struct RequestTimeline: Hashable, Sendable {
    var request: GroupPaymentRequest
    var title: String
}

/// One thing that happened to a request, before a run of them is collapsed into a row.
nonisolated struct RequestOccurrence {

    enum Kind: Hashable {
        /// A share paid in Flipcash, drawn from `message`.
        case sharePayment(message: ConversationMessage, amount: FiatAmount)
        /// A share the creator marked paid.
        case markedPaid
        /// The request closed by its creator.
        case closed
    }

    var kind: Kind
    var requestID: PaymentRequestID
    /// The request's creator: who was paid, who marked, who closed.
    var creator: UserID?
    /// Who paid, or whose share was marked; nil for a close.
    var member: UserID?
    var date: Date

    /// The id of the row a run starting at this occurrence draws as.
    var rowID: String {
        switch kind {
        case .sharePayment(let message, _): "req-paid-\(message.stableID)"
        case .markedPaid:                   "req-marked-\(requestID.data.hexString())-\(member?.uuidString ?? "")"
        case .closed:                       "req-closed-\(requestID.data.hexString())"
        }
    }

    /// Whether `other`, drawn directly below, joins this one's row.
    func collapses(with other: RequestOccurrence) -> Bool {
        guard requestID == other.requestID else { return false }
        switch (kind, other.kind) {
        case (.sharePayment, .sharePayment), (.markedPaid, .markedPaid): return true
        case (.sharePayment, _), (.markedPaid, _), (.closed, _):         return false
        }
    }
}

nonisolated extension RequestOccurrence {

    /// The marked-paid and closed occurrences `requests` hold, oldest first. Neither has a message
    /// behind it: a mark is a share settled by hand at its `paidAt`, a close a `closed` status at
    /// `closedAt`.
    static func stored(in requests: [PaymentRequestID: RequestTimeline]) -> [RequestOccurrence] {
        var occurrences: [RequestOccurrence] = []
        for timeline in requests.values {
            let request = timeline.request
            for share in request.split?.shares ?? [] {
                guard let paidAt = share.paidAt, let userID = share.userID else { continue }
                switch share.settlement {
                case .manual:
                    occurrences.append(RequestOccurrence(kind: .markedPaid, requestID: request.id, creator: request.creator, member: userID, date: paidAt))
                case .intent, .creator, .unknown, nil:
                    continue
                }
            }
            switch request.status {
            case .closed:
                if let closedAt = request.closedAt {
                    occurrences.append(RequestOccurrence(kind: .closed, requestID: request.id, creator: request.creator, member: nil, date: closedAt))
                }
            case .open, .completed, .expired, .unknown:
                break
            }
        }
        // Ties are ordered by id so a remap of the same store draws the same rows.
        return occurrences.sorted { ($0.date, $0.rowID) < ($1.date, $1.rowID) }
    }

    /// The row a run of occurrences that collapse together draws as. `request` is the run's request
    /// when it is stored and readable; without it a share payment draws no title or ring and does
    /// not tap through.
    static func row(
        for run: [RequestOccurrence],
        request: RequestTimeline?,
        selfUserID: UserID,
        nameOf: (UserID) -> String?
    ) -> ChatRequestEvent? {
        guard let first = run.first, let last = run.last else { return nil }
        func name(_ id: UserID?) -> ChatRequestEvent.Span {
            if id == selfUserID { return .viewer("you") }
            return .name(id.flatMap(nameOf).flatMap { $0.isEmpty ? nil : $0 } ?? "Someone")
        }
        func leading(_ id: UserID?) -> ChatRequestEvent.Span {
            id == selfUserID ? .viewer("You") : name(id)
        }
        let members = run.map(\.member)
        let viewerIsMember = members.contains(selfUserID)
        func others(_ count: Int) -> String { "\(count) \(count == 1 ? "other" : "others")" }
        typealias Span = ChatRequestEvent.Span

        switch first.kind {
        case .sharePayment:
            var messages: [ConversationMessage] = []
            var total: FiatAmount?
            for occurrence in run {
                guard case .sharePayment(let message, let amount) = occurrence.kind else { continue }
                messages.append(message)
                // One viewer currency per transcript, so the run's amounts add.
                total = total.map { $0.currency == amount.currency ? $0 + amount : $0 } ?? amount
            }
            let caption: [Span]
            if run.count == 1 {
                caption = if first.member == selfUserID {
                    [.viewer("You"), Span(" paid")]
                } else if first.creator == nil {
                    // The message names no receiver and the request isn't stored to say who.
                    [name(first.member), Span(" paid")]
                } else {
                    [name(first.member), Span(" paid "), name(first.creator)]
                }
            } else if viewerIsMember {
                caption = [.viewer("You"), Span(" and \(others(run.count - 1)) paid")]
            } else if first.creator == selfUserID {
                caption = [Span("\(run.count) people paid "), .viewer("you")]
            } else {
                caption = [Span("\(run.count) people paid")]
            }
            // The newest confirmed payment is what the READ pointer moves past.
            let serverID = messages.last { $0.status == .sent }?.id
            return ChatRequestEvent(
                id: first.rowID,
                kind: .sharePayment,
                caption: caption,
                amount: total?.formattedDroppingZeroFraction(),
                title: request?.title,
                ringFraction: request.map { $0.request.paidFraction(asOfShareOf: last.member, fallback: last.date) },
                requestID: request.map { $0.request.id.data },
                serverID: serverID,
                messageIDs: messages.map(\.stableID)
            )

        case .markedPaid:
            guard let request else { return nil }
            let caption: [Span]
            if run.count == 1 {
                caption = [leading(first.creator), Span(" marked "), name(first.member), Span(" as paid")]
            } else if viewerIsMember {
                caption = [leading(first.creator), Span(" marked "), .viewer("you"), Span(" and \(others(run.count - 1)) as paid")]
            } else {
                caption = [leading(first.creator), Span(" marked \(run.count) people as paid")]
            }
            return ChatRequestEvent(
                id: first.rowID,
                kind: .markedPaid,
                caption: caption,
                title: request.title,
                ringFraction: request.request.paidFraction(asOf: last.date),
                requestID: request.request.id.data
            )

        case .closed:
            guard let request else { return nil }
            return ChatRequestEvent(
                id: first.rowID,
                kind: .closed,
                caption: [leading(first.creator), Span(" closed")],
                title: request.title,
                requestID: request.request.id.data
            )
        }
    }
}

nonisolated extension GroupPaymentRequest {

    /// The paid fraction as of `payer`'s payment: every share paid at or before their share's
    /// `paidAt`. A copy that doesn't show the share paid yet counts it at `fallback`, the payment
    /// message's date, so the row never draws a ring short of its own payment.
    func paidFraction(asOfShareOf payer: UserID?, fallback: Date) -> Double {
        let paidAt = payer.flatMap { share(for: $0) }?.paidAt
        return paidFraction(asOf: paidAt ?? fallback, counting: payer)
    }
}
