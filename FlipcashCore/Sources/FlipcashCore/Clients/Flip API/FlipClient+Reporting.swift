//
//  FlipClient+Reporting.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

extension FlipClient {

    /// Files a report against a user, chat, message, or blob. Advisory only — the server never
    /// surfaces an outcome back to the reporter, and reporting the same target again is a no-op.
    public func report(owner: KeyPair, target: ReportTarget, description: String? = nil) async throws {
        try await withCheckedThrowingContinuation { c in
            reportingService.report(owner: owner, target: target, description: description) { c.resume(with: $0) }
        }
    }
}
