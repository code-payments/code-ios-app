//
//  ReasonClassifier.swift
//  Code
//
//  Created by Raul Riera on 2026-04-29.
//

import Foundation
import FlipcashCore

/// Matches free-form server reason strings against case-insensitive
/// fragment lists and returns a typed classification.
///
/// Designed for `ErrorSubmitIntent.staleState`-style failure modes where
/// the server returns informational strings that callers want to switch
/// on. Add a `ReasonClassifier<Classification>` per call site, declare
/// the fragment lists for each known shape, and let unknown reasons
/// fall through to the fallback.
struct ReasonClassifier<Classification> {

    /// One classification rule: if any reason in the input contains any
    /// of `fragments` (case-insensitive), invoke `make` with the
    /// *original* matching reason string and return the result.
    struct Rule {
        let fragments: [String]
        let make: (String) -> Classification
    }

    private let rules: [Rule]
    private let fallback: ([String]) -> Classification

    init(rules: [Rule], fallback: @escaping ([String]) -> Classification) {
        self.rules = rules
        self.fallback = fallback
    }

    /// Classifies the reason array. Tests every rule against every
    /// reason in order; first match wins. If nothing matches, returns
    /// `fallback(reasons)`.
    func classify(_ reasons: [String]) -> Classification {
        for reason in reasons {
            let normalized = reason.lowercased()
            for rule in rules {
                if rule.fragments.contains(where: { normalized.contains($0.lowercased()) }) {
                    return rule.make(reason)
                }
            }
        }
        return fallback(reasons)
    }
}

// MARK: - ErrorSubmitIntent classification -

/// Classification for an `ErrorSubmitIntent.staleState` reason array as
/// observed in the cash-link flows. Add new cases here as new reason
/// shapes show up in production.
enum CashLinkStaleStateReason: Equatable {
    /// Server says the gift card has already been claimed/voided/expired.
    /// Benign user-flow race (someone else redeemed first).
    case alreadyClaimed
    /// Server says the *client's* cached balance version is stale —
    /// real client/server desync.
    case staleClientCache(reason: String)
    /// Reason string we haven't classified yet.
    case other
}

extension ErrorSubmitIntent {
    /// Returns the classification of this error's `staleState` reasons,
    /// or `nil` if the error is a different `ErrorSubmitIntent` case.
    /// Use to disambiguate the benign "already claimed" race from a real
    /// stale-cache desync at catch sites.
    var cashLinkStaleStateReason: CashLinkStaleStateReason? {
        guard case .staleState(let reasons) = self else { return nil }
        return Self.cashLinkStaleStateClassifier.classify(reasons)
    }

    /// `true` when the error is `.denied` (server-side guard refusal:
    /// spam, money laundering, rate/policy). The app can't act on a
    /// denial — it's not a bug — so callers should surface a user
    /// dialog without reporting to Bugsnag.
    var isDenied: Bool {
        if case .denied = self { return true }
        return false
    }

    private static let cashLinkStaleStateClassifier = ReasonClassifier<CashLinkStaleStateReason>(
        rules: [
            .init(
                fragments: ["already been claimed", "already claimed"],
                make: { _ in .alreadyClaimed }
            ),
            .init(
                fragments: ["cached balance version is stale", "stale balance version"],
                make: { .staleClientCache(reason: $0) }
            ),
        ],
        fallback: { _ in .other }
    )
}
