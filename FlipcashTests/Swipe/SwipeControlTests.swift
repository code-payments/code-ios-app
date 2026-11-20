//
//  SwipeControlTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CoreGraphics
import Testing
@testable import FlipcashUI

@Suite("SwipeControl commit threshold")
struct SwipeControlTests {

    @Test("Past 70% of the track commits at any speed")
    func commitsPastSeventyPercent() {
        #expect(SwipeControl.shouldCommit(percent: 0.71, velocity: 0))
        #expect(SwipeControl.shouldCommit(percent: 1.0, velocity: -500))
    }

    @Test("At or below 70% a slow release snaps back")
    func slowReleaseBelowSeventyPercentSnapsBack() {
        #expect(!SwipeControl.shouldCommit(percent: 0.69, velocity: 0))
        #expect(!SwipeControl.shouldCommit(percent: 0.7, velocity: 200))
    }

    @Test("Past 50% a fling faster than 200 points commits")
    func flingPastHalfCommits() {
        #expect(SwipeControl.shouldCommit(percent: 0.51, velocity: 201))
        #expect(!SwipeControl.shouldCommit(percent: 0.51, velocity: 200))
    }

    @Test("At or below 50% even a fast fling snaps back")
    func flingBelowHalfSnapsBack() {
        #expect(!SwipeControl.shouldCommit(percent: 0.49, velocity: 1000))
        #expect(!SwipeControl.shouldCommit(percent: 0.5, velocity: 1000))
    }
}
