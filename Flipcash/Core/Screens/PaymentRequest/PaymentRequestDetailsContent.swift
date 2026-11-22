//
//  PaymentRequestDetailsContent.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Request details put into words for one viewer.
struct PaymentRequestDetailsContent: Hashable {

    /// What tapping a share row does.
    enum RowAction: Hashable {
        case none
        /// The creator may mark this unpaid share paid.
        case markPaid
    }

    struct Row: Identifiable, Hashable {
        let userID: UserID
        let name: String
        let amount: String
        let status: String
        let isPaid: Bool
        let action: RowAction

        var id: UserID { userID }
    }

    /// The large title over the summary; `nil` for a collection, which has none.
    let title: String?
    let requestedBy: String
    let amounts: String
    /// The line under ``amounts``; empty hides it.
    let statusLine: String
    let rows: [Row]
    /// "No payments yet" in place of the rows of a collection nobody has paid into.
    let emptyLine: String?
    /// The viewer's unpaid share when they can pay it now; `nil` hides "Pay <amount>".
    let payableShare: GroupPaymentRequest.Share?
    /// "Pay $20" for ``payableShare``.
    let payTitle: String?
    /// Whether the "•••" menu with Close Request shows.
    let canClose: Bool
    let isEnded: Bool

    /// `name` gives a member's display name; the viewer's own row reads "You".
    init(
        request: GroupPaymentRequest,
        title: String,
        viewer: UserID,
        hasPaymentIntent: Bool,
        copy: PaymentRequestCopy,
        now: Date,
        name: (UserID) -> String
    ) {
        let isOpen: Bool
        switch request.effectiveStatus(at: now) {
        case .open:                                    isOpen = true
        case .completed, .closed, .expired, .unknown:  isOpen = false
        }
        let isCreator = request.creator == viewer

        self.title = title
        emptyLine = nil
        if isCreator {
            requestedBy = "Requested by you"
        } else {
            requestedBy = "Requested by \(request.creator.map(name) ?? "")"
        }
        amounts = copy.progressLine(request)
        statusLine = PaymentRequestCopy.statusLine(request.deadline(at: now))
        isEnded = !isOpen
        canClose = isOpen && isCreator

        rows = (request.split?.shares ?? []).compactMap { share in
            guard let userID = share.userID else { return nil }
            let action: RowAction = isOpen && isCreator && !share.isPaid && userID != viewer ? .markPaid : .none
            return Row(
                userID: userID,
                name: userID == viewer ? "You" : name(userID),
                amount: copy.shareText(share, of: request),
                status: PaymentRequestCopy.shareStatus(share, requestIsOpen: isOpen),
                isPaid: share.isPaid,
                action: action
            )
        }

        if isOpen, !isCreator, hasPaymentIntent, let own = request.share(for: viewer), !own.isPaid {
            payableShare = own
            payTitle = "Pay \(copy.shareText(own, of: request))"
        } else {
            payableShare = nil
            payTitle = nil
        }
    }

    /// A collection put into words: no title, "<total paid> paid · <amount> each", "Closed" once
    /// closed, a row for each paid payer newest first, and "Pay <amount>" while the viewer may pay.
    /// `paidPayers` is `nil` until a page is read, and `viewerHasPaid` until a read of the request
    /// answers; Pay shows only once that read says the viewer hasn't paid. `nil` when the amount kind
    /// isn't one this build knows.
    init?(
        collection request: GroupPaymentRequest,
        paidPayers: [GroupPaymentRequest.Payer]?,
        viewerHasPaid: Bool?,
        viewer: UserID,
        copy: PaymentRequestCopy,
        now: Date,
        name: (UserID) -> String
    ) {
        guard let amounts = copy.collectionDetailsAmounts(request), let each = copy.collectionAmount(request) else { return nil }
        let isOpen: Bool
        switch request.effectiveStatus(at: now) {
        case .open:                                    isOpen = true
        case .completed, .closed, .expired, .unknown:  isOpen = false
        }
        let isCreator = request.creator == viewer

        title = nil
        if isCreator {
            requestedBy = "Requested by you"
        } else {
            requestedBy = "Requested by \(request.creator.map(name) ?? "")"
        }
        self.amounts = amounts
        statusLine = request.status == .closed ? PaymentRequestCopy.statusLine(.closed) : ""
        isEnded = !isOpen
        canClose = isOpen && isCreator

        rows = (paidPayers ?? []).compactMap { payer in
            guard let userID = payer.userID, payer.isPaid else { return nil }
            return Row(
                userID: userID,
                name: userID == viewer ? "You" : name(userID),
                amount: copy.collectionPaid(payer, of: request),
                status: "✓ Paid",
                isPaid: true,
                action: .none
            )
        }
        emptyLine = paidPayers != nil && rows.isEmpty ? "No payments yet" : nil

        payableShare = nil
        payTitle = isOpen && !isCreator && viewerHasPaid == false ? "Pay \(each.formatted())" : nil
    }
}

extension GroupPaymentRequest {

    /// Whether a widget sent by `sender` in `conversationID` may render this request. A request
    /// from another chat, or one the sender did not create, renders as unsupported.
    func belongs(to conversationID: ConversationID, sentBy sender: UserID?) -> Bool {
        chatID == conversationID && creator != nil && creator == sender
    }
}

extension PaymentRequestDetailsContent {

    /// The details of `request` as `requests` holds it, or nil until it can draw: a collection once it is drawable, a split once its title reads.
    @MainActor
    static func reading(
        _ request: GroupPaymentRequest,
        in requests: PaymentRequests,
        viewer: UserID,
        hasPaymentIntent: Bool,
        copy: PaymentRequestCopy,
        now: Date,
        name: (UserID) -> String
    ) -> PaymentRequestDetailsContent? {
        if request.collection != nil {
            guard requests.isDrawable(request) else { return nil }
            return PaymentRequestDetailsContent(
                collection: request,
                paidPayers: requests.payers.paidPayers(of: request.id),
                viewerHasPaid: requests.payers.hasPaid(request.id, viewer: viewer),
                viewer: viewer,
                copy: copy,
                now: now,
                name: name
            )
        }
        guard let text = requests.text(of: request) else { return nil }
        return PaymentRequestDetailsContent(
            request: request,
            title: text.displayTitle,
            viewer: viewer,
            hasPaymentIntent: hasPaymentIntent,
            copy: copy,
            now: now,
            name: name
        )
    }
}
