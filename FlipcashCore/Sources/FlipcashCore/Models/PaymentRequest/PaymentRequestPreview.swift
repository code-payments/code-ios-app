//
//  PaymentRequestPreview.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

extension ChatPaymentRequestContent.Card {
    /// Words `request` for the viewer: amounts in their currency, the deadline as of `now`.
    public init(request: GroupPaymentRequest, title: String, copy: PaymentRequestCopy, now: Date) {
        self.init(
            title: title,
            progressLine: copy.progressLine(request),
            fraction: request.paidFraction,
            statusLine: PaymentRequestCopy.statusLine(request.deadline(at: now)),
            isEnded: request.isEnded(at: now)
        )
    }
}

/// What a notification shows for a pushed payment request: the banner line and the transcript card.
public struct PaymentRequestPreview: Hashable, Sendable {
    /// The banner body, like "Sam sent request for Dinner · $20".
    public let body: String
    /// The card for the expanded transcript; nil when the request's title can't be opened.
    public let card: ChatPaymentRequestContent.Card?

    /// Words `request` for `viewer`, opening its title with `seal` when it is encrypted. The chat list's
    /// "sent request for <title>" line, with the amount `viewer` owes, else the request's total.
    /// `senderName` leads the line when the push's title doesn't already name the sender.
    public init(
        request: GroupPaymentRequest,
        seal: ChatSeal?,
        viewer: UserID,
        senderName: String?,
        copy: PaymentRequestCopy,
        now: Date
    ) {
        let currency = request.split?.currency ?? ""
        let text = PaymentRequestText(request: request, seal: seal)
        let amount: String = request.share(for: viewer).map { copy.shareText($0, of: request) }
            ?? copy.viewerAmount(request.requestedNative, currency: currency)?.formattedDroppingZeroFraction()
            ?? ""

        let firstName = senderName.flatMap { $0.split(separator: " ").first.map(String.init) }
        var line = firstName.map { "\($0) sent request" } ?? "Request"
        if let title = text?.title { line += " for \(title)" }
        if !amount.isEmpty { line += " · \(amount)" }

        self.body = line
        self.card = text.map { Card(request: request, title: $0.title, copy: copy, now: now) }
    }

    private typealias Card = ChatPaymentRequestContent.Card
}
