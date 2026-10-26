//
//  PaymentRequestAutoExpand.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The owed requests this device has already opened the deck for, so it opens itself once per
/// request.
@MainActor
struct PaymentRequestAutoExpand {

    /// How long the deck stays open on its own before it collapses into the strip.
    static let duration: Duration = .seconds(2.5)

    private static let key = "PaymentRequestAutoExpand.shown"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The requests among `owed` the deck hasn't opened for yet, now remembered as shown.
    mutating func claim(_ owed: [PaymentRequestID]) -> [PaymentRequestID] {
        var shown = Set(defaults.stringArray(forKey: Self.key) ?? [])
        let fresh = owed.filter { !shown.contains($0.data.base64EncodedString()) }
        guard !fresh.isEmpty else { return [] }
        shown.formUnion(fresh.map { $0.data.base64EncodedString() })
        defaults.set(Array(shown), forKey: Self.key)
        return fresh
    }
}
