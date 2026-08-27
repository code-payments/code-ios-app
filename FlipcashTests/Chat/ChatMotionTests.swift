//
//  ChatMotionTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import QuartzCore
import ChatLayout
import FlipcashCore
@testable import FlipcashUI

@Suite("ChatSpring physics")
struct ChatSpringPhysicsTests {

    /// One row of the motion spec's published derivation table. The spec derived these
    /// independently of this code, so they pin the conversion rather than restate it.
    struct Row: Sendable {
        let name: String
        let spring: ChatSpring
        let dampingRatio: Double
        let stiffness: Double
        let damping: Double
    }

    static let rows: [Row] = [
        Row(name: "insertion",      spring: ChatMotion.insertion,      dampingRatio: 0.73, stiffness: 746.3,  damping: 39.88),
        Row(name: "scroll",         spring: ChatMotion.scroll,         dampingRatio: 0.88, stiffness: 438.6,  damping: 36.86),
        Row(name: "keyboardScroll", spring: ChatMotion.keyboardScroll, dampingRatio: 1.00, stiffness: 438.6,  damping: 41.89),
        Row(name: "delivered",      spring: ChatMotion.delivered,      dampingRatio: 0.88, stiffness: 246.7,  damping: 27.65),
        Row(name: "read",           spring: ChatMotion.read,           dampingRatio: 0.74, stiffness: 584.0,  damping: 35.77),
        Row(name: "swap",           spring: ChatMotion.swap,           dampingRatio: 0.69, stiffness: 541.5,  damping: 32.11),
        Row(name: "sendButton",     spring: ChatMotion.sendButton,     dampingRatio: 0.66, stiffness: 1366.0, damping: 48.79),
        Row(name: "corner",         spring: ChatMotion.corner,         dampingRatio: 0.68, stiffness: 195.0,  damping: 18.99),
    ]

    @Test("Derived physics match the spec's table", arguments: rows)
    func derivationMatchesSpec(row: Row) {
        #expect(abs(row.spring.dampingRatio - row.dampingRatio) < 0.005, "\(row.name) damping ratio")
        #expect(abs(row.spring.stiffness - row.stiffness) < 0.1, "\(row.name) stiffness")
        #expect(abs(row.spring.damping - row.damping) < 0.01, "\(row.name) damping")
    }

    @Test("Layer animations carry the derived physics", arguments: rows)
    func layerAnimationCarriesPhysics(row: Row) {
        let animation = row.spring.layerAnimation(keyPath: "path")
        #expect(animation.keyPath == "path")
        #expect(animation.mass == 1)
        #expect(abs(animation.stiffness - row.stiffness) < 0.1, "\(row.name) stiffness")
        #expect(abs(animation.damping - row.damping) < 0.01, "\(row.name) damping")
    }

    @Test("A layer animation runs for its settling time, not its perceptual duration")
    func layerAnimationRunsToSettling() {
        let animation = ChatMotion.corner.layerAnimation(keyPath: "path")
        // Cutting the animation off at the perceptual duration would snap the remaining travel.
        #expect(animation.duration == animation.settlingDuration)
        #expect(animation.duration > ChatMotion.corner.duration)
    }

    @Test("Zero bounce is critically damped")
    func zeroBounceIsCriticallyDamped() {
        #expect(ChatMotion.keyboardScroll.dampingRatio == 1)
    }
}

@MainActor
@Suite("Insertion geometry")
struct ChatInsertionStateTests {

    private func attributes(width: CGFloat = 400) -> ChatLayoutAttributes {
        let attributes = ChatLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.frame = CGRect(x: 0, y: 0, width: width, height: 50)
        return attributes
    }

    @Test("An outgoing insert is anchored to the trailing edge, an incoming one to the leading edge")
    func insertionStateAnchorsToSendersEdge() {
        // Scaling a 400pt row to 0.95 loses 20pt of width; half of that is the centre shift needed to
        // hold one edge still.
        let expectedShift: CGFloat = 10

        let outgoing = attributes()
        let outgoingCentre = outgoing.center.x
        ChatMotion.applyInsertionState(to: outgoing, sender: .me)
        #expect(outgoing.alpha == 0)
        #expect(outgoing.transform.a == ChatMotion.insertionScale)
        #expect(abs(outgoing.center.x - (outgoingCentre + expectedShift)) < 0.001)

        let incoming = attributes()
        let incomingCentre = incoming.center.x
        ChatMotion.applyInsertionState(to: incoming, sender: .other)
        #expect(abs(incoming.center.x - (incomingCentre - expectedShift)) < 0.001)
    }

    @Test("A row with no sender scales about its own centre")
    func insertionStateWithoutSenderDoesNotShift() {
        let attributes = attributes()
        let centre = attributes.center.x
        ChatMotion.applyInsertionState(to: attributes, sender: nil)
        #expect(attributes.alpha == 0)
        #expect(attributes.transform.a == ChatMotion.insertionScale)
        #expect(attributes.center.x == centre)
    }
}
