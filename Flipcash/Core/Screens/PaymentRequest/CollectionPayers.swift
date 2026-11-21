//
//  CollectionPayers.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

/// The payers of the collections read this session: each one's paid list, and the viewer's own part.
///
/// A paid list comes from the first `GetPayers` page and carries the request version it was read at;
/// a live payer update applies only past that version, replacing the payer by user id. The viewer's
/// part comes from `GetPaymentRequest`; none is held until a read of the request answers, so a
/// stored copy never offers Pay to someone who already paid. Nothing here is stored.
@MainActor
@Observable
final class CollectionPayers {

    /// A collection's paid payers, newest first, at the request version they were read at.
    struct Paid: Hashable {
        var payers: [GroupPaymentRequest.Payer]
        var version: UInt64
    }

    /// The viewer's part in a collection as the last read of it returned: `nil` when they haven't paid in.
    struct Caller: Hashable {
        let payer: GroupPaymentRequest.Payer?
    }

    private var paid: [PaymentRequestID: Paid] = [:]
    private var callers: [PaymentRequestID: Caller] = [:]

    /// `id`'s paid payers, newest first; `nil` until a page has been read.
    func paidPayers(of id: PaymentRequestID) -> [GroupPaymentRequest.Payer]? {
        paid[id]?.payers
    }

    /// Whether `viewer` has paid into `id`, as the reads this session say; `nil` until a read of the
    /// request has answered.
    func hasPaid(_ id: PaymentRequestID, viewer: UserID?) -> Bool? {
        guard let caller = callers[id] else { return nil }
        if caller.payer?.isPaid == true { return true }
        guard let viewer else { return false }
        return paid[id]?.payers.contains { $0.userID == viewer && $0.isPaid } ?? false
    }

    /// Whether `id`'s paid list is held, so a refetch of the request also rereads it.
    func isTracking(_ id: PaymentRequestID) -> Bool {
        paid[id] != nil
    }

    /// Records the viewer's part in `id` from a read of the request.
    func record(caller payer: GroupPaymentRequest.Payer?, for id: PaymentRequestID) {
        let caller = Caller(payer: payer)
        if callers[id] != caller { callers[id] = caller }
    }

    /// Takes a freshly read first page unless a live update has already moved the list past it.
    func record(page payers: [GroupPaymentRequest.Payer], version: UInt64, for id: PaymentRequestID) {
        if let held = paid[id], held.version > version { return }
        let page = Paid(payers: payers.filter(\.isPaid), version: version)
        if paid[id] != page { paid[id] = page }
    }

    /// Applies one live update's payers at `version`. Dropped when no list is held or the list was
    /// read at or past `version`.
    func apply(_ payers: [GroupPaymentRequest.Payer], version: UInt64, to id: PaymentRequestID) {
        guard !payers.isEmpty, var held = paid[id], version > held.version else { return }
        for payer in payers {
            held.payers.removeAll { $0.userID == payer.userID }
            if payer.isPaid { held.payers.insert(payer, at: 0) }
        }
        held.version = version
        paid[id] = held
    }

    /// Drops what is held for `ids`.
    func forget(_ ids: some Sequence<PaymentRequestID>) {
        for id in ids {
            paid[id] = nil
            callers[id] = nil
        }
    }
}
