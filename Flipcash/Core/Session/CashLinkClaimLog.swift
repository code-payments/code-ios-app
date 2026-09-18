//
//  CashLinkClaimLog.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The cash links this device has finished trying to claim, by the entropy their URL carries.
///
/// A link card memoizes what the server said about a link, and nothing arrives to tell it that the
/// answer has changed: there is no event for "this link was claimed". A claim settling on this
/// device is the one moment the memo is known to be wrong — the transcript behind the sheet still
/// reads "Tap to claim" for a link that is now spent — so the claim path names the entropy here and
/// whoever renders it asks again.
///
/// Only settled attempts are recorded. A denial or a dropped connection says nothing about the
/// link, and re-asking on those would turn every failed tap into a round trip.
@MainActor @Observable
final class CashLinkClaimLog {

    private(set) var settled: Set<String> = []

    /// Records that a claim of `entropy` reached an end — collected, already collected, or expired.
    func record(entropy: String) {
        settled.insert(entropy)
    }
}
