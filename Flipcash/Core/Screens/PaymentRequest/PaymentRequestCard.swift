//
//  PaymentRequestCard.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashUI
import FlipcashCore

/// What a request card shows, already put into words.
typealias PaymentRequestCardContent = ChatPaymentRequestContent.Card

extension ChatPaymentRequestContent.Card {
    /// Words `request` for the viewer: amounts in their currency, the deadline as of `now`.
    init(request: GroupPaymentRequest, title: String, copy: PaymentRequestCopy, now: Date) {
        self.init(
            title: title,
            progressLine: copy.progressLine(request),
            fraction: request.paidFraction,
            statusLine: PaymentRequestCopy.statusLine(request.deadline(at: now)),
            isEnded: request.isEnded(at: now)
        )
    }
}
