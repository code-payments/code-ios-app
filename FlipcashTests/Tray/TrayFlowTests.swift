//
//  TrayFlowTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import Testing
@testable import FlipcashUI

@MainActor
@Suite("TrayFlow")
struct TrayFlowTests {

    @Test("A new flow shows its root with nothing to go back to")
    func startsAtRoot() {
        let flow = TrayFlow(root: "education")

        #expect(flow.path == ["education"])
        #expect(flow.current == "education")
        #expect(!flow.canGoBack)
        #expect(flow.direction == .forward)
    }

    @Test("Pushing moves forward to the new step")
    func pushMovesForward() {
        let flow = TrayFlow(root: "education")

        flow.push("address")

        #expect(flow.path == ["education", "address"])
        #expect(flow.current == "address")
        #expect(flow.canGoBack)
        #expect(flow.direction == .forward)
    }

    @Test("Going back returns to the previous step and records the direction")
    func backReturns() {
        let flow = TrayFlow(root: "education")
        flow.push("address")
        flow.push("confirm")

        flow.back()

        #expect(flow.current == "address")
        #expect(flow.direction == .back)
    }

    @Test("The X goes back a step from the second step on")
    func closeGoesBack() {
        let flow = TrayFlow(root: "education")
        flow.push("address")
        var dismissed = false

        flow.close { dismissed = true }

        #expect(flow.current == "education")
        #expect(flow.direction == .back)
        #expect(!dismissed)
    }

    @Test("The X dismisses on the root")
    func closeDismissesOnRoot() {
        let flow = TrayFlow(root: "education")
        var dismissed = false

        flow.close { dismissed = true }

        #expect(dismissed)
        #expect(flow.path == ["education"])
    }

    @Test("Going back on the root does nothing")
    func backOnRootIsIgnored() {
        let flow = TrayFlow(root: "education")

        flow.back()

        #expect(flow.path == ["education"])
        #expect(flow.direction == .forward)
    }
}

@MainActor
@Suite("TrayAction")
struct TrayActionTests {

    @Test("The secondary sits left of the primary whatever order they are given in")
    func secondaryOrdersFirst() {
        let actions = [
            TrayAction("Share") {},
            TrayAction("Don't Share", role: .secondary) {},
        ]

        let ordered = TrayAction.ordered(actions).map(\.title)

        #expect(ordered == ["Don't Share", "Share"])
    }

    @Test("A destructive action takes the primary's place")
    func destructiveTakesPrimarySlot() {
        let destructive = TrayAction("Log Out", role: .destructive) {}
        let primary = TrayAction("OK") {}
        let secondary = TrayAction("Cancel", role: .secondary) {}

        #expect(destructive.slot == primary.slot)
        #expect(TrayAction.ordered([destructive, secondary]).map(\.title) == ["Cancel", "Log Out"])
    }

    @Test(
        "An action takes taps only while enabled and not showing progress",
        arguments: [
            (ButtonState.normal, true, true),
            (ButtonState.normal, false, false),
            (ButtonState.loading, true, false),
            (ButtonState.success, true, false),
        ]
    )
    func interactivity(state: ButtonState, isEnabled: Bool, expected: Bool) {
        let action = TrayAction("Save", state: state, isEnabled: isEnabled) {}

        #expect(action.isInteractive == expected)
    }
}

@MainActor
@Suite("TrayMetrics")
struct TrayMetricsTests {

    @Test("Type keeps its tuned size at the default Dynamic Type category")
    func scaledKeepsDefault() {
        #expect(TrayMetrics.scaled(24, .title2, .large) == 24)
        #expect(TrayMetrics.scaled(15, .subheadline, .large) == 15)
    }

    @Test("Type grows at larger categories and shrinks at smaller ones")
    func scaledFollowsCategory() {
        #expect(TrayMetrics.scaled(24, .title2, .accessibility3) > 24)
        #expect(TrayMetrics.scaled(24, .title2, .xSmall) < 24)
    }

    @Test("Reduce Motion turns the scale press into a dim and leaves the others alone")
    func reduceMotionPress() {
        #expect(TrayActionPress.scale.resolved(reduceMotion: true) == .dim)
        #expect(TrayActionPress.scale.resolved(reduceMotion: false) == .scale)
        #expect(TrayActionPress.none.resolved(reduceMotion: true) == .none)
        #expect(TrayActionPress.dim.resolved(reduceMotion: true) == .dim)
    }

    @Test("Only the error style fades the card red")
    func onlyErrorFadesRed() {
        #expect(!TrayStyle.standard.fadesRed)
        #expect(!TrayStyle.success.fadesRed)
        #expect(TrayStyle.error.fadesRed)
    }

    @Test("Central icons match by name across steps; images never match")
    func iconIdentity() {
        #expect(TrayIcon.central(.lock).identity == TrayIcon.central(.lock).identity)
        #expect(TrayIcon.central(.lock).identity != TrayIcon.central(.clock).identity)
        #expect(TrayIcon.image(Image(systemName: "lock")).identity == nil)
    }

    @Test("A destructive tray shows the exclamation circle")
    func destructiveIcon() {
        #expect(TrayIcon.destructive.identity == TrayIcon.central(.exclamationCircle).identity)
    }
}
