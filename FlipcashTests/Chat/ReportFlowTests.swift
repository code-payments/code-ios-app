//
//  ReportFlowTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import FlipcashCore
@testable import Flipcash

// `@MainActor` for the same reason `MessageCapabilityMenuTests` is: the labels are an app-target
// extension, so their isolation is the app's default.
@MainActor
@Suite("Report flow")
struct ReportFlowTests {

    // MARK: - Which step a reason leads to

    @Test("Something Else collects details; every other reason files on confirm")
    func onlyOtherNeedsDetails() {
        for reason in ReportReason.displayOrder where reason != .other {
            #expect(
                ReportFlowState.needsDetails(reason) == false,
                "\(reason.title) should file without a second step"
            )
        }
        #expect(ReportFlowState.needsDetails(.other))
    }

    @Test("The button says which of the two it will do")
    func buttonTitleNamesTheOutcome() {
        #expect(ReportFlowState.buttonTitle(for: .other) == "Next")
        for reason in ReportReason.displayOrder where reason != .other {
            #expect(ReportFlowState.buttonTitle(for: reason) == "Submit Report")
        }
        // Nothing picked yet: the button is disabled, but it should not be blank while it waits.
        #expect(ReportFlowState.buttonTitle(for: nil) == "Submit Report")
    }

    @Test("Whitespace is not an answer")
    func detailsMustSaySomething() {
        #expect(ReportFlowState.canSubmitDetails("") == false)
        #expect(ReportFlowState.canSubmitDetails("   \n\t ") == false)
        #expect(ReportFlowState.canSubmitDetails("  they kept messaging me  "))
    }

    // MARK: - Every reason has words on it

    // The compiler cannot check a `switch` over a Kotlin enum for exhaustiveness, so this stands in
    // for one: a reason added upstream arrives in `displayOrder` and fails here.
    @Test("Every reason carries a label, a line of scope, and a slug")
    func presentationIsTotal() {
        for reason in ReportReason.displayOrder {
            #expect(reason.title.isEmpty == false, "a reason is showing no label")
            #expect(reason.summary.isEmpty == false, "\(reason.title) has no line of scope")
            #expect(reason.identifier.isEmpty == false, "\(reason.title) has no slug")
        }

        let identifiers = Set(ReportReason.displayOrder.map(\.identifier))
        #expect(
            identifiers.count == ReportReason.displayOrder.count,
            "two reasons share an accessibility identifier"
        )
    }

    // MARK: - What reaches the wire

    // These read the shared builder rather than anything here: they fail if iOS ever starts
    // assembling the `description` itself, which is the drift the shared module exists to prevent.

    @Test("No details is the bare token, with nothing trailing it")
    func blankDetailsGiveABareToken() {
        let built = ReportDescription.build(reason: .spam, details: nil)
        #expect(built.contains("\n") == false)
        #expect(built == ReportDescription.build(reason: .spam, details: "   "))
    }

    @Test("Details follow the token on the next line, trimmed")
    func detailsFollowTheToken() {
        let built = ReportDescription.build(reason: .other, details: "  they kept messaging me  ")
        let lines = built.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[1] == "they kept messaging me")
        // The first line is the token alone, so a server-side reader can split on the newline.
        #expect(lines[0] == ReportDescription.build(reason: .other, details: nil))
    }

    @Test("Over-long details are truncated, not refused")
    func longDetailsAreTruncated() {
        let cap = Int(ReportDescription.maxDetailsLength)
        let built = ReportDescription.build(reason: .other, details: String(repeating: "a", count: cap + 50))
        let lines = built.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[1].count == cap)
    }
}
