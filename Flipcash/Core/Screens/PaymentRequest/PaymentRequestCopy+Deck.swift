//
//  PaymentRequestCopy+Deck.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

extension PaymentRequestCopy {
    /// The deck's VoiceOver label: "<N> requests, <title>, <viewer status>, <paid> of <requested> paid, <status>".
    func deckAccessibilityLabel(front: GroupPaymentRequest, title: String, viewerStatus: PaymentRequestViewerStatus, count: Int, now: Date) -> String {
        let parts = [title, viewerStatus.accessibilityText, "\(deckAmounts(front)) paid", Self.statusLine(front.deadline(at: now))]
        let summary = parts.compactMap { $0 }.joined(separator: ", ")
        return count > 1 ? "\(count) requests, \(summary)" : summary
    }
}
