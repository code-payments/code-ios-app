//
//  PaymentRequestTitleValidator.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Validates a payment request's title, returning it trimmed.
public struct PaymentRequestTitleValidator: Validator {

    /// PGV `max_len` on `paymentrequest.v1.PaymentRequestText.title`, which counts Unicode scalars.
    public static let maxScalars = 100

    public init() {}

    public func validate(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= Self.maxScalars else {
            return nil
        }

        return trimmed
    }
}
