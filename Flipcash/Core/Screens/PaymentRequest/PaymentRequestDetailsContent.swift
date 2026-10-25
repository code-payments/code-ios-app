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

    let title: String
    let requestedBy: String
    let amounts: String
    let statusLine: String
    let rows: [Row]
    /// The viewer's unpaid share when they can pay it now; `nil` hides "Send <amount>".
    let payableShare: GroupPaymentRequest.Share?
    /// "Send $20" for ``payableShare``.
    let sendTitle: String?
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
            sendTitle = "Send \(copy.shareText(own, of: request))"
        } else {
            payableShare = nil
            sendTitle = nil
        }
    }
}

extension GroupPaymentRequest {

    /// Whether a widget sent by `sender` in `conversationID` may render this request. A request
    /// from another chat, or one the sender did not create, renders as unsupported.
    func belongs(to conversationID: ConversationID, sentBy sender: UserID?) -> Bool {
        chatID == conversationID && creator != nil && creator == sender
    }
}
