//
//  FlipClient+GroupPaymentRequest.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

extension FlipClient {

    /// Creates a split in the group chat `chatID`. Reuse `idempotencyKey` across retries.
    public func createPaymentRequest(owner: KeyPair, idempotencyKey: Data, chatID: ConversationID, split: GroupPaymentRequest.Split) async throws -> GroupPaymentRequest {
        try await withCheckedThrowingContinuation { c in
            paymentRequestService.createPaymentRequest(owner: owner, idempotencyKey: idempotencyKey, chatID: chatID, split: split) { c.resume(with: $0) }
        }
    }

    /// Fetches one request. `paymentIntentID` is the intent id a caller holding an unpaid share of a
    /// split must use for the payment, and `nil` for anyone else, a collection's payers included.
    /// `callerPayer` is the caller's own part in the request, when they have one.
    public func getPaymentRequest(owner: KeyPair, id: PaymentRequestID) async throws -> (request: GroupPaymentRequest, paymentIntentID: Data?, callerPayer: GroupPaymentRequest.Payer?) {
        let fetched: PaymentRequestService.Fetched = try await withCheckedThrowingContinuation { c in
            paymentRequestService.getPaymentRequest(owner: owner, id: id) { c.resume(with: $0) }
        }
        return (fetched.request, fetched.paymentIntentID, fetched.callerPayer)
    }

    /// The intent id the caller pays `id` under. A collection's payers get it only from here; reuse it
    /// across every retry of one payment.
    public func getPaymentIntentID(owner: KeyPair, id: PaymentRequestID) async throws -> Data {
        try await withCheckedThrowingContinuation { c in
            paymentRequestService.getPaymentIntentID(owner: owner, id: id) { c.resume(with: $0) }
        }
    }

    /// One page of `id`'s payers in `section`, with the token for the next page when there is one and
    /// the request version the page was read at. A collection's payer list has no bound, so this does
    /// not page to exhaustion.
    public func getPayersPage(owner: KeyPair, id: PaymentRequestID, section: GroupPaymentRequest.PayerSection, pageSize: Int, pagingToken: Data?) async throws -> (payers: [GroupPaymentRequest.Payer], nextPagingToken: Data?, version: UInt64) {
        let page: PaymentRequestService.PayersPage = try await withCheckedThrowingContinuation { c in
            paymentRequestService.getPayers(owner: owner, id: id, section: section, pageSize: pageSize, pagingToken: pagingToken) { c.resume(with: $0) }
        }
        return (page.payers, page.hasMore ? page.pagingToken : nil, page.version)
    }

    /// Every request in `conversationID` for `section`, paged to exhaustion.
    public func getChatPaymentRequests(owner: KeyPair, conversationID: ConversationID, section: GroupPaymentRequest.Section) async throws -> [GroupPaymentRequest] {
        var all: [GroupPaymentRequest] = []
        var pagingToken: Data?

        while true {
            let page: PaymentRequestService.ChatPage = try await withCheckedThrowingContinuation { c in
                paymentRequestService.getChatPaymentRequests(owner: owner, conversationID: conversationID, section: section, pagingToken: pagingToken) { c.resume(with: $0) }
            }
            all.append(contentsOf: page.requests)
            guard page.hasMore else { break }
            pagingToken = page.pagingToken
        }
        return all
    }

    /// One page of `conversationID`'s requests for `section`, with the token for the next page when
    /// there is one.
    public func getChatPaymentRequestsPage(owner: KeyPair, conversationID: ConversationID, section: GroupPaymentRequest.Section, pageSize: Int, pagingToken: Data?) async throws -> (requests: [GroupPaymentRequest], nextPagingToken: Data?) {
        let page: PaymentRequestService.ChatPage = try await withCheckedThrowingContinuation { c in
            paymentRequestService.getChatPaymentRequests(owner: owner, conversationID: conversationID, section: section, pageSize: pageSize, pagingToken: pagingToken) { c.resume(with: $0) }
        }
        return (page.requests, page.hasMore ? page.pagingToken : nil)
    }

    /// Closes an open request. Creator only.
    public func closePaymentRequest(owner: KeyPair, id: PaymentRequestID) async throws -> GroupPaymentRequest {
        try await withCheckedThrowingContinuation { c in
            paymentRequestService.closePaymentRequest(owner: owner, id: id) { c.resume(with: $0) }
        }
    }

    /// Marks `userID`'s share paid out of band. Creator only.
    public func markPaid(owner: KeyPair, id: PaymentRequestID, userID: UserID) async throws -> GroupPaymentRequest {
        try await withCheckedThrowingContinuation { c in
            paymentRequestService.markPaid(owner: owner, id: id, userID: userID) { c.resume(with: $0) }
        }
    }
}
