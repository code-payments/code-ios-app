//
//  ReportFlowState.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashUI

/// What has been chosen so far, and how far through the report we are.
///
/// Held apart from ``ReportFlowScreen`` because stepping to the details and back must not lose the
/// pick that got you there, nor the words already typed — going back is usually a second thought
/// about the reason, not about what happened. A `@State` on the step's own view dies with the step.
@Observable
final class ReportFlowState {

    /// Picking a reason, and — for ``ReportReason/other`` alone — saying what happened.
    enum Step: Equatable {
        case reason
        case details
    }

    var step: Step = .reason

    /// Nil until a row is picked. The button waits on it.
    var selectedReason: ReportReason?

    var details: String = ""

    /// Carries the send: the wait, then the checkmark, on whichever step submitted.
    var buttonState: ButtonState = .normal

    /// Whether picking this reason needs a second step before there is a report worth filing.
    ///
    /// `nonisolated` and static so the branch is reachable from a test without standing up a view.
    nonisolated static func needsDetails(_ reason: ReportReason) -> Bool {
        reason == .other
    }

    /// What the button will do, spelled on the button, because it differs by row.
    nonisolated static func buttonTitle(for reason: ReportReason?) -> String {
        reason.map { needsDetails($0) ? "Next" : "Submit Report" } ?? "Submit Report"
    }

    /// Whitespace alone is not an answer, and this is the same trim
    /// ``ReportDescription/build(reason:details:)`` applies — so the button and the wire agree on
    /// what "blank" means.
    nonisolated static func canSubmitDetails(_ details: String) -> Bool {
        !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
