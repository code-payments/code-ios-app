//
//  ReportReason+Presentation.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The words each reason wears, and the slug it answers to in a test.
///
/// Kept here rather than on the shared enum: ``ReportReason`` is compiled for both platforms, and
/// each app writes its own copy against it. What must not differ is the token
/// ``ReportDescription/build(reason:details:)`` puts on the wire, and that never comes from here.
///
/// A table rather than a `switch`, because a Kotlin enum arrives in Swift as a class and the
/// compiler cannot check a `switch` over one for exhaustiveness. `ReportReasonPresentationTests`
/// does that check instead, walking ``ReportReason/displayOrder``, so a reason added upstream fails
/// a test here instead of shipping a row with no words on it.
extension ReportReason {

    /// The row's label.
    var title: String {
        Self.presentation[self]?.title ?? ""
    }

    /// One line of scope under the label.
    ///
    /// Six words of label leave people guessing which bucket their situation belongs in, and a
    /// guess resolves as the nearest wrong one — which costs both the reporter and whoever reads
    /// it. These say what the row collects, and promise nothing about what happens next.
    var summary: String {
        Self.presentation[self]?.summary ?? ""
    }

    /// Stable slug for accessibility identifiers. Not the wire token — that is the shared
    /// builder's to decide.
    var identifier: String {
        Self.presentation[self]?.identifier ?? ""
    }

    private struct Presentation {
        let title: String
        let summary: String
        let identifier: String
    }

    private static let presentation: [ReportReason: Presentation] = [
        .spam: Presentation(
            title: "Spam",
            summary: "Repeated unwanted messages, promotions, or links",
            identifier: "spam"
        ),
        .scamorfraud: Presentation(
            title: "Scam or Fraud",
            summary: "Attempts to take money or account details by deception",
            identifier: "scam-or-fraud"
        ),
        .harassment: Presentation(
            title: "Harassment or Bullying",
            summary: "Abuse, insults, or repeated unwanted contact",
            identifier: "harassment"
        ),
        .sexualcontent: Presentation(
            title: "Sexual Content",
            summary: "Explicit content, or unwanted sexual messages",
            identifier: "sexual-content"
        ),
        .violence: Presentation(
            title: "Violence or Threats",
            summary: "Threats of harm, or content showing violence",
            identifier: "violence"
        ),
        .other: Presentation(
            title: "Something Else",
            summary: "None of these fit — tell us in your own words",
            identifier: "other"
        ),
    ]
}
