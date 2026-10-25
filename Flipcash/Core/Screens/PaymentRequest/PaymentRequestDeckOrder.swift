//
//  PaymentRequestDeckOrder.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The deck's view-only cycling: how many times the front card was sent to the back since the deck
/// last returned to its default order.
struct PaymentRequestDeckOrder: Hashable {

    /// The pill's height fraction a downward drag must pass to finish a cycle.
    static let cycleThreshold: CGFloat = 0.4

    private(set) var rotation = 0

    /// `requests`, in default deck order, rotated by the cycles made so far.
    func apply(to requests: [GroupPaymentRequest]) -> [GroupPaymentRequest] {
        guard requests.count > 1 else { return requests }
        let shift = rotation % requests.count
        return Array(requests[shift...] + requests[..<shift])
    }

    /// Sends the front card to the back.
    mutating func cycle() {
        rotation += 1
    }

    /// Returns to the default order, as every refetch and every reopen of the chat does.
    mutating func reset() {
        rotation = 0
    }

    /// Whether a drag of `translation` points over a pill `height` points tall, ending at
    /// `predictedTranslation`, finishes a cycle.
    static func finishesCycle(translation: CGFloat, predictedTranslation: CGFloat, height: CGFloat) -> Bool {
        guard height > 0 else { return false }
        return translation > height * cycleThreshold || predictedTranslation > height * 1.5
    }
}
