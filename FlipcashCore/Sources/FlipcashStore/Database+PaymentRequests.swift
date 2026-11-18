//
//  Database+PaymentRequests.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {

    // MARK: - Get -

    /// The stored requests of one chat, in no particular order. A row that no longer decodes is skipped.
    public func paymentRequests(in conversationID: ConversationID) throws -> [GroupPaymentRequest] {
        let p = PaymentRequestTable()
        return try reader.prepareRowIterator(p.table.filter(p.conversationID == conversationID.data))
            .compactMap { GroupPaymentRequest(serializedMetadata: $0[p.metadata]) }
    }

    /// The stored copy of one request, if any.
    public func paymentRequest(id: PaymentRequestID) throws -> GroupPaymentRequest? {
        let p = PaymentRequestTable()
        return try reader.pluck(p.table.filter(p.id == id.data)).flatMap {
            GroupPaymentRequest(serializedMetadata: $0[p.metadata])
        }
    }

    // MARK: - Write -

    /// Stores each request under the merge rule the contract gives a client: the greater version wins,
    /// and at an equal version EXPIRED beats OPEN. It is one statement per request, evaluated against
    /// the stored row, so a stale copy can't overwrite a newer one whatever order writes arrive in.
    public func upsertPaymentRequests(_ requests: [GroupPaymentRequest]) throws {
        guard !requests.isEmpty else { return }
        let open = GroupPaymentRequest.Status.open.wireValue
        let expired = GroupPaymentRequest.Status.expired.wireValue
        try write { writer in
            try writer.transaction(.immediate) {
                for request in requests {
                    let metadata = try request.serializedMetadata()
                    try writer.run(
                        """
                        INSERT INTO paymentRequest (id, conversationID, version, status, endsAt, createdAt, metadata)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            conversationID = excluded.conversationID,
                            version = excluded.version,
                            status = excluded.status,
                            endsAt = excluded.endsAt,
                            createdAt = excluded.createdAt,
                            metadata = excluded.metadata
                        WHERE excluded.version > paymentRequest.version
                           OR (excluded.version = paymentRequest.version
                               AND excluded.status = ? AND paymentRequest.status = ?)
                        """,
                        request.id.data.datatypeValue,
                        request.chatID?.data.datatypeValue,
                        request.version.datatypeValue,
                        request.status.wireValue,
                        request.split?.endsAt?.timeIntervalSinceReferenceDate,
                        request.createdAt?.timeIntervalSinceReferenceDate,
                        metadata.datatypeValue,
                        expired,
                        open
                    )
                }
            }
        }
    }
}
